// motor_sprites.v
// Motor de 32 sprites 16x16.
// Movimento e atributos recebidos da UC (sinais internos derivados da ISA).
// Nao ha entradas de botoes/chaves da placa neste motor.

module motor_sprites (
   input  wire        clk,
   input  wire        reset_n,
   input  wire [8:0]  x_logico,
   input  wire [7:0]  y_logico,
   input  wire [2:0]  movimento_isa,   // sinais internos da UC; ativos em 0
   input  wire [8:0]  atributos_isa,
   output reg  [7:0]  indice_cor,
   output wire        pixel_valido,
   output wire [8:0]  sprite_x_debug,
   output wire [7:0]  sprite_y_debug,
   output wire [4:0]  sprite_id_debug,
   output wire        direcao_debug
);

   wire [4:0] selecao_sprite = atributos_isa[4:0];
   wire sw_transparencia = atributos_isa[7];
   wire sw_mirror_h      = atributos_isa[6];
   wire sw_mirror_v      = atributos_isa[5];
   wire sw_visivel       = atributos_isa[8];

   reg [8:0] sprite_x [0:31];
   reg [7:0] sprite_y [0:31];
   reg [4:0] sprite_pat [0:31];      // 0..31: indice do padrao real na sprite_rom
   reg       sprite_en [0:31];
   reg       sprite_mirror_h [0:31];
   reg       sprite_mirror_v [0:31];
   reg       sprite_transp [0:31];

   // ------------------------------------------------------------------
   // Movimento suave ~70 Hz
   // ------------------------------------------------------------------
   reg [18:0] contador_velocidade;
   wire pulso_movimento = (contador_velocidade == 19'd349999);

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n)
         contador_velocidade <= 19'd0;
      else if (pulso_movimento)
         contador_velocidade <= 19'd0;
      else
         contador_velocidade <= contador_velocidade + 19'd1;
   end

   // O sinal interno de direcao alterna os dois sentidos de movimento.
   // Sincronizacao + borda + bloqueio curto evitam repetir a troca de modo.
   reg key1_sync0, key1_sync1, key1_anterior;
   reg [18:0] debounce_key1;
   reg modo_direcao;
   wire key1_press = key1_anterior && !key1_sync1 && (debounce_key1 == 19'd0);

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         key1_sync0 <= 1'b1;
         key1_sync1 <= 1'b1;
         key1_anterior <= 1'b1;
         debounce_key1 <= 19'd0;
         modo_direcao <= 1'b0;
      end else begin
         key1_sync0 <= movimento_isa[0];
         key1_sync1 <= key1_sync0;
         key1_anterior <= key1_sync1;

         if (key1_press) begin
            modo_direcao <= ~modo_direcao;
            debounce_key1 <= 19'd250000;
         end else if (debounce_key1 != 19'd0) begin
            debounce_key1 <= debounce_key1 - 19'd1;
         end
      end
   end

   wire key3_ativo = !movimento_isa[2];
   wire key2_ativo = !movimento_isa[1];

   // Atributos + movimento
   integer k;
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         for (k = 0; k < 32; k = k + 1) begin
            // Grade segura dentro de 320x240.
            sprite_x[k] <= 9'd16 + ((k % 8) * 9'd36);
            sprite_y[k] <= 8'd16 + ((k / 8) * 8'd52);
            sprite_pat[k] <= k[4:0];
            sprite_en[k] <= 1'b0; // sprites aparecem somente apos comando ISA visivel=1
            sprite_mirror_h[k] <= 1'b0;
            sprite_mirror_v[k] <= 1'b0;
            sprite_transp[k] <= 1'b1;
         end
      end else begin
         // As chaves editam os atributos do registro atualmente enderecado.
         sprite_transp[selecao_sprite]  <= sw_transparencia;
         sprite_mirror_h[selecao_sprite] <= sw_mirror_h;
         sprite_mirror_v[selecao_sprite] <= sw_mirror_v;
         sprite_en[selecao_sprite] <= sw_visivel;

         if (pulso_movimento) begin
            if (!modo_direcao) begin
               // modo 0: eixo X decrementa e eixo Y incrementa.
               if (key3_ativo && sprite_x[selecao_sprite] > 9'd0)
                  sprite_x[selecao_sprite] <= sprite_x[selecao_sprite] - 9'd1;
               if (key2_ativo && sprite_y[selecao_sprite] < 8'd224)
                  sprite_y[selecao_sprite] <= sprite_y[selecao_sprite] + 8'd1;
            end else begin
               // modo 1: eixo X incrementa e eixo Y decrementa.
               if (key3_ativo && sprite_x[selecao_sprite] < 9'd304)
                  sprite_x[selecao_sprite] <= sprite_x[selecao_sprite] + 9'd1;
               if (key2_ativo && sprite_y[selecao_sprite] > 8'd0)
                  sprite_y[selecao_sprite] <= sprite_y[selecao_sprite] - 8'd1;
            end
         end
      end
   end

   assign sprite_x_debug  = sprite_x[selecao_sprite];
   assign sprite_y_debug  = sprite_y[selecao_sprite];
   assign sprite_id_debug = selecao_sprite;
   assign direcao_debug   = modo_direcao;

   // Busca do sprite que cobre o pixel.
   // Indice 0 = maior prioridade (fica por cima).
   // O loop varre de 0 a 31; o primeiro encontrado trava a selecao.
   // ------------------------------------------------------------------
   reg       pixel_encontrado;
   reg [3:0] px_local;
   reg [3:0] py_local;
   reg [4:0] pat_local;
   reg       transp_local;
   reg       pixel_encontrado_d;
   reg       transp_local_d;
   integer idx;
   reg [8:0] dx_local;
   reg [7:0] dy_local;

   always @(*) begin
      pixel_encontrado = 1'b0;
      px_local = 4'd0;
      py_local = 4'd0;
      pat_local = 5'd0;
      transp_local = 1'b1;
      dx_local = 9'd0;
      dy_local = 8'd0;

      // Varredura de 0 até 31 garante prioridade absoluta para o Sprite 00
      for (idx = 0; idx <= 31; idx = idx + 1) begin
         if (!pixel_encontrado && sprite_en[idx] &&
            x_logico >= sprite_x[idx] && x_logico < sprite_x[idx] + 9'd16 &&
            y_logico >= sprite_y[idx] && y_logico < sprite_y[idx] + 8'd16) begin

            pixel_encontrado = 1'b1;
            dx_local = x_logico - sprite_x[idx];
            dy_local = y_logico - sprite_y[idx];
            px_local = sprite_mirror_h[idx] ? (4'd15 - dx_local[3:0]) : dx_local[3:0];
            py_local = sprite_mirror_v[idx] ? (4'd15 - dy_local[3:0]) : dy_local[3:0];
            pat_local = sprite_pat[idx];
            transp_local = sprite_transp[idx];
         end
      end
   end

   // Padroes de sprite armazenados em ROM dedicada (sprite_rom.v + sprite_patterns.mif)
   wire [7:0] cor_rom;
   sprite_rom rom_sprites (
       .address ({pat_local, py_local, px_local}),
       .clock   (clk),
       .rden    (1'b1),
       .q       (cor_rom)
   );

   // Transparencia e independente da visibilidade do sprite:
   // invisivel nao gera pixel; transparente torna apenas a cor zero vazada.
   // Metadados atrasados um clock para acompanhar a saida registrada da ROM.
   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         pixel_encontrado_d <= 1'b0;
         transp_local_d <= 1'b1;
      end else begin
         pixel_encontrado_d <= pixel_encontrado;
         transp_local_d <= transp_local;
      end
   end

   assign pixel_valido = pixel_encontrado_d && (!transp_local_d || cor_rom != 8'd0);
   always @(*) begin
      if (pixel_valido) indice_cor = cor_rom;
      else indice_cor = 8'd0;
   end

endmodule
