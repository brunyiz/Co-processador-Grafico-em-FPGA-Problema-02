// unidade_controle.v
// Unidade de controle unica para SPRITE, TILE, SCROLL, TRIANGULO e RETANGULO.
// O modulo e o arquivo foram renomeados para unidade_controle.
// TILE: opcode 0001, [27:22] X, [21:17] Y, [7:0] cor RGB332.
// SCROLL: opcode 0110, [27:26] direcao, [25:22] quantidade de tiles.
// Direcao da camera: 00 direita, 01 esquerda, 10 cima, 11 baixo.
// TRIANGULO: tres palavras opcode 0100. [27:26] etapa, [25:17] X,
// [16:9] Y, [8:1] cor. Etapas 00=P1+cor, 01=P2, 10=P3+desenhar.
// RETANGULO: duas palavras opcode 0011. [27:26] etapa, [25:17] X,
// [16:9] Y, [8:1] cor. Etapas 00=P1+cor, 01=P2+desenhar.
// Um pulso aplica cada comando; a FIFO mantem o IR ate done.
// O motor_sprites.v recebe sinais internos de controle produzidos pela ISA;
// nenhum botao/chave fisico participa da operacao.
//
// Instrucao tratada: SPRITE - POSICIONAR (opcode 0010)
//   [31:28] opcode  [27:23] id  [22:14] x  [13:6] y
//   [5] visivel     [4:3] espelhamento (bit3 = H, bit4 = V)
//   [2] transparente; [1:0] reservado
//
// A UC traduz os campos da instrucao em atributos e sinais internos de movimento.
//
// Posicionamento em malha fechada: a UC le a posicao real do sprite e gera
// sinais internos de movimento ate igualar X/Y ao alvo da instrucao.

module unidade_controle (
   input  wire        clk,
   input  wire        reset_n,

   // Interface de instrucao (handshake valid / busy / done)
   input  wire        instr_valid,
   input  wire [31:0] instr,
   input  wire        inicio_vblank,
   output wire        busy,
   output reg         done,
   output reg         instr_invalida,

   // Sinais internos ISA->motor de sprites (nao conectados a pinos da placa).
   output reg  [2:0]  sprite_movimento_isa,
   output reg  [8:0]  sprite_atributos_isa,

   // Escrita simples no tilemap do background
   output reg         tile_wr_en,
   output reg  [5:0]  tile_wr_x,
   output reg  [4:0]  tile_wr_y,
   output reg  [7:0]  tile_wr_cor,

   // Scroll relativo em tiles, aplicado pelo background no proximo clock.
   output reg         scroll_atualizar,
   output reg  [1:0]  scroll_direcao,
   output reg  [3:0]  scroll_quantidade,

   // Dados para o rasterizador. O pulso tri_desenhar indica que P3 chegou.
   output reg         tri_desenhar,
   output wire [8:0]  tri_x1, tri_x2, tri_x3,
   output wire [7:0]  tri_y1, tri_y2, tri_y3,
   output wire [7:0]  tri_cor,

   // Dados para retangulo/quadrado. O pulso ret_desenhar ocorre na palavra 2.
   output reg         ret_desenhar,
   output wire [8:0]  ret_x1, ret_x2,
   output wire [7:0]  ret_y1, ret_y2,
   output wire [7:0]  ret_cor,

   // Realimentacao (saidas de debug do motor_sprites)
   input  wire [8:0]  sprite_x_atual,
   input  wire [7:0]  sprite_y_atual,
   input  wire        modo_direcao_atual
);

   localparam [3:0] OP_TILE   = 4'b0001,
                    OP_SPRITE = 4'b0010,
                    OP_RETANGULO = 4'b0011,
                    OP_TRIANGULO = 4'b0100,
                    OP_VSYNC = 4'b0101,
                    OP_SCROLL = 4'b0110;

   // Limites de movimento impostos pelo proprio motor
   localparam [8:0] X_MAX = 9'd304;
   localparam [7:0] Y_MAX = 8'd224;

   localparam [2:0] IDLE    = 3'd0,
                    SETTLE  = 3'd1,
                    RUN     = 3'd2,
                    TOG     = 3'd3,
                    TOGWAIT = 3'd4,
                    WAIT_VBLANK = 3'd5;

   reg [2:0]  estado;
   reg [17:0] cnt;
   reg [8:0]  alvo_x;
   reg [7:0]  alvo_y;

   assign busy = (estado != IDLE);

   // Campos da instrucao
   wire [3:0] opcode  = instr[31:28];
   wire [4:0] f_id    = instr[27:23];
   wire [8:0] f_x     = instr[22:14];
   wire [7:0] f_y     = instr[13:6];
   wire       f_vis   = instr[5];
   wire       f_mh    = instr[3];
   wire       f_mv    = instr[4];
   wire       f_transp= instr[2];

   // Formato do comando TILE (opcode 0001):
   // [31:28] opcode | [27:22] tile_x | [21:17] tile_y | [16:8] reservado | [7:0] cor RGB332
   wire [5:0] tile_x_cmd   = instr[27:22];
   wire [4:0] tile_y_cmd   = instr[21:17];
   wire [7:0] tile_cor_cmd = instr[7:0];

   // Campos do scroll: quantidade 1..15; bits [21:0] reservados.
   wire [1:0] scroll_dir_cmd = instr[27:26];
   wire [3:0] scroll_qtd_cmd = instr[25:22];

   // Cada palavra de triangulo e completa por si: nao existe campo cortado.
   wire [1:0] tri_etapa_cmd = instr[27:26];
   wire [8:0] tri_x_cmd     = instr[25:17];
   wire [7:0] tri_y_cmd     = instr[16:9];
   wire [7:0] tri_cor_cmd   = instr[8:1];
   reg  [1:0] tri_etapa; // 0=espera P1, 1=espera P2, 2=espera P3

   // Mesmo formato do triangulo, mas com somente dois pontos.
   reg  ret_etapa; // 0=espera P1, 1=espera P2

   // Comparacao posicao atual x alvo
   wire x_inc, x_dec, y_inc, y_dec;
   wire [31:0] dp_r0, dp_r1, dp_r2, dp_r3, dp_r4, dp_r5, dp_r6, dp_r7;
   reg dp_write;
   reg [2:0] dp_addr;
   reg [31:0] dp_data;
   wire tri_etapa_valida = (tri_etapa == 2'd0 && tri_etapa_cmd == 2'd0) ||
                           (tri_etapa == 2'd1 && tri_etapa_cmd == 2'd1) ||
                           (tri_etapa == 2'd2 && tri_etapa_cmd == 2'd2);
   wire ret_etapa_valida = (!ret_etapa && tri_etapa_cmd == 2'd0) ||
                           (ret_etapa && tri_etapa_cmd == 2'd1);

   datapath_grafico datapath (
      .clk(clk), .reset_n(reset_n), .reg_write(dp_write), .reg_addr(dp_addr),
      .reg_data(dp_data), .r0(dp_r0), .r1(dp_r1), .r2(dp_r2), .r3(dp_r3),
      .r4(dp_r4), .r5(dp_r5), .r6(dp_r6), .r7(dp_r7),
      .sprite_x(sprite_x_atual), .alvo_x(alvo_x),
      .sprite_y(sprite_y_atual), .alvo_y(alvo_y),
      .x_menor(x_inc), .x_maior(x_dec), .y_menor(y_inc), .y_maior(y_dec)
   );

   // P1 armazena tambem a cor em [7:0]; P2/P3 ocupam somente X/Y.
   assign tri_x1 = dp_r0[24:16]; assign tri_y1 = dp_r0[15:8];
   assign tri_cor = dp_r0[7:0];
   assign tri_x2 = dp_r1[16:8];  assign tri_y2 = dp_r1[7:0];
   assign tri_x3 = dp_r2[16:8];  assign tri_y3 = dp_r2[7:0];
   assign ret_x1 = dp_r3[24:16]; assign ret_y1 = dp_r3[15:8];
   assign ret_cor = dp_r3[7:0];
   assign ret_x2 = dp_r4[16:8];  assign ret_y2 = dp_r4[7:0];

   // Decodificacao de escrita do banco: somente etapas aceitas pela ISA.
   always @(*) begin
      dp_write = 1'b0; dp_addr = 3'd0; dp_data = 32'd0;
      if (instr_valid && estado == IDLE && opcode == OP_TRIANGULO && tri_etapa_valida) begin
         dp_write = 1'b1;
         case (tri_etapa_cmd)
            2'd0: begin dp_addr = 3'd0; dp_data = {7'd0, tri_x_cmd, tri_y_cmd, tri_cor_cmd}; end
            2'd1: begin dp_addr = 3'd1; dp_data = {15'd0, tri_x_cmd, tri_y_cmd}; end
            2'd2: begin dp_addr = 3'd2; dp_data = {15'd0, tri_x_cmd, tri_y_cmd}; end
         endcase
      end else if (instr_valid && estado == IDLE && opcode == OP_RETANGULO && ret_etapa_valida) begin
         dp_write = 1'b1;
         if (!ret_etapa) begin dp_addr = 3'd3; dp_data = {7'd0, tri_x_cmd, tri_y_cmd, tri_cor_cmd}; end
         else begin dp_addr = 3'd4; dp_data = {15'd0, tri_x_cmd, tri_y_cmd}; end
      end
   end

   // Qual sinal interno move cada eixo no modo atual?
   //   modo 0: X-- e Y++; modo 1: X++ e Y--.
   wire k3 = modo_direcao_atual ? x_inc : x_dec;
   wire k2 = modo_direcao_atual ? y_dec : y_inc;

   wire falta_mover = x_inc | x_dec | y_inc | y_dec;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         estado         <= IDLE;
         cnt            <= 18'd0;
         done           <= 1'b0;
         instr_invalida <= 1'b0;
         sprite_movimento_isa <= 3'b111;
         sprite_atributos_isa <= 9'd0;
         tile_wr_en     <= 1'b0;
         tile_wr_x      <= 6'd0;
         tile_wr_y      <= 5'd0;
         tile_wr_cor    <= 8'd0;
         scroll_atualizar  <= 1'b0;
         scroll_direcao    <= 2'd0;
         scroll_quantidade <= 4'd0;
         tri_desenhar <= 1'b0;
         tri_etapa <= 2'd0;
         ret_desenhar <= 1'b0;
         ret_etapa <= 1'b0;
         alvo_x         <= 9'd0;
         alvo_y         <= 8'd0;
      end else begin
         done       <= 1'b0;
         tile_wr_en <= 1'b0;   // pulso de somente 1 ciclo
         scroll_atualizar <= 1'b0; // nao repetir o mesmo comando
         tri_desenhar <= 1'b0; // nao redesenhar sem uma terceira palavra
         ret_desenhar <= 1'b0; // nao redesenhar sem a segunda palavra

         case (estado)
            // ---------------------------------------------------------
            IDLE: begin
               sprite_movimento_isa <= 3'b111;
               if (instr_valid) begin
                  if (opcode == OP_TILE) begin
                     // Alterar um tile e terminar imediatamente.
                     // A RAM do background grava no mesmo clock.
                     if ((tile_x_cmd < 6'd40) && (tile_y_cmd < 5'd30)) begin
                        instr_invalida <= 1'b0;
                        tile_wr_x      <= tile_x_cmd;
                        tile_wr_y      <= tile_y_cmd;
                        tile_wr_cor    <= tile_cor_cmd;
                        tile_wr_en     <= 1'b1;
                     end else begin
                        instr_invalida <= 1'b1;
                     end
                     done <= 1'b1;
                  end else if (opcode == OP_SCROLL) begin
                     if (scroll_qtd_cmd != 4'd0) begin
                        instr_invalida    <= 1'b0;
                        scroll_direcao    <= scroll_dir_cmd;
                        scroll_quantidade <= scroll_qtd_cmd;
                        scroll_atualizar  <= 1'b1;
                     end else begin
                        instr_invalida <= 1'b1;
                     end
                     // No proximo flanco, o motor aplica o pulso e a FIFO
                     // observa done. Nao e necessario criar outra UC.
                     done <= 1'b1;
                  end else if (opcode == OP_VSYNC) begin
                     if (instr[27:0] == 28'd0) begin
                        instr_invalida <= 1'b0;
                        estado <= WAIT_VBLANK;
                     end else begin
                        instr_invalida <= 1'b1;
                        done <= 1'b1;
                     end
                  end else if (opcode == OP_RETANGULO) begin
                     // Dois pontos opostos, igual ao uso manual antigo do
                     // rasterizador: P1+cor e depois P2+desenhar.
                     if (!ret_etapa && (tri_etapa_cmd == 2'd0)) begin
                        ret_etapa <= 1'b1;
                        instr_invalida <= 1'b0;
                     end else if (ret_etapa && (tri_etapa_cmd == 2'd1)) begin
                        ret_desenhar <= 1'b1;
                        ret_etapa <= 1'b0;
                        instr_invalida <= 1'b0;
                     end else begin
                        ret_etapa <= 1'b0;
                        instr_invalida <= 1'b1;
                     end
                     done <= 1'b1;
                  end else if (opcode == OP_TRIANGULO) begin
                     // Tres instrucoes de 32 bits, sempre na ordem P1, P2, P3.
                     // Cada uma termina imediatamente; a FIFO nao precisa mudar.
                     if ((tri_etapa == 2'd0) && (tri_etapa_cmd == 2'd0)) begin
                        tri_etapa <= 2'd1;
                        instr_invalida <= 1'b0;
                     end else if ((tri_etapa == 2'd1) && (tri_etapa_cmd == 2'd1)) begin
                        tri_etapa <= 2'd2;
                        instr_invalida <= 1'b0;
                     end else if ((tri_etapa == 2'd2) && (tri_etapa_cmd == 2'd2)) begin
                        tri_desenhar <= 1'b1;
                        tri_etapa <= 2'd0;
                        instr_invalida <= 1'b0;
                     end else begin
                        tri_etapa <= 2'd0;
                        instr_invalida <= 1'b1;
                     end
                     done <= 1'b1;
                  end else if (opcode == OP_SPRITE) begin
                     instr_invalida <= 1'b0;
                     alvo_x <= (f_x > X_MAX) ? X_MAX : f_x;
                     alvo_y <= (f_y > Y_MAX) ? Y_MAX : f_y;
                     // Seleciona o sprite e aplica atributos no MESMO ciclo
                     sprite_atributos_isa <= { f_vis, f_transp, f_mh, f_mv, f_id };
                     cnt    <= 18'd0;
                     estado <= SETTLE;
                  end else begin
                     instr_invalida <= 1'b1;   // opcode nao tratado: ignora
                     done           <= 1'b1;
                  end
               end
            end

            // ---------------------------------------------------------
            // Espera o motor registrar a nova selecao/atributos
            SETTLE: begin
               if (cnt == 18'd3) begin
                  cnt    <= 18'd0;
                  estado <= RUN;
               end else
                  cnt <= cnt + 18'd1;
            end

            // ---------------------------------------------------------
            // Mantem movimento interno enquanto houver caminho no modo atual.
            RUN: begin
               if (k3 || k2) begin
                  sprite_movimento_isa <= { ~k3, ~k2, 1'b1 };
               end else begin
                  sprite_movimento_isa <= 3'b111;
                  if (falta_mover) begin       // direcao errada: inverte o modo
                     cnt    <= 18'd0;
                     estado <= TOG;
                  end else begin               // chegou ao alvo
                     done   <= 1'b1;
                     estado <= IDLE;
                  end
               end
            end

            // ---------------------------------------------------------
            // Pulso interno que alterna o sentido dos eixos.
            TOG: begin
               sprite_movimento_isa <= 3'b110;
               if (cnt == 18'd7) begin
                  cnt         <= 18'd0;
                  sprite_movimento_isa <= 3'b111;
                  estado      <= TOGWAIT;
               end else
                  cnt <= cnt + 18'd1;
            end

            // ---------------------------------------------------------
            // Aguarda a protecao contra repeticao de troca de sentido do motor.
            TOGWAIT: begin
               if (cnt == 18'd255_000) begin
                  cnt    <= 18'd0;
                  estado <= RUN;
               end else
                  cnt <= cnt + 18'd1;
            end

            // Barreira de quadro: mantem a FIFO ocupada ate o inicio do VBlank.
            WAIT_VBLANK: begin
               sprite_movimento_isa <= 3'b111;
               if (inicio_vblank) begin
                  done <= 1'b1;
                  estado <= IDLE;
               end
            end

            default: estado <= IDLE;
         endcase
      end
   end

endmodule
