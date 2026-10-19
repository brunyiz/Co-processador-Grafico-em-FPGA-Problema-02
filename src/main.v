// main.v
// Centralizador do nucleo do coprocessador grafico.
// Conecta os geradores de clock, sincronismo de video, decodificador de comandos,
// motores graficos (background, sprites, poligonos), compositor e paleta de cores.
// Alinhado com as portas fisicas em maiusculas especificadas no top-level 'DE1_SOC_golden_top.v'.

module main (
	// PIOs exportados pelo soc_system: entrada passiva de comandos.
	input  wire [31:0] GPU_CMD,
	input  wire        GPU_REQ,
	input  wire        HPS_RESET_N,
	output wire [31:0] GPU_STATUS,
	// Clocks e Resets da Placa DE1-SoC (Sinais de Entrada Fisicos)
	input  wire        CLOCK_50,         // Clock de 50 MHz vindo da placa (CLOCK_50)
	input  wire [3:0]  KEY,              // Botoes mecanicos da placa (KEY[3:0]), ativos em 0
	input  wire [9:0]  SW,               // Chaves deslizantes da placa (SW[9:0])

	// Feedbacks Visuais da Placa (LEDs e Displays de Saida)
	output wire [9:0]  LEDR,             // LEDs vermelhos de status da placa (LEDR[9:0])
	output wire [6:0]  HEX0,             // Segmentos do display de 7 seg 0 (HEX0)
	output wire [6:0]  HEX1,             // Segmentos do display de 7 seg 1 (HEX1)
	output wire [6:0]  HEX2,             // Segmentos do display de 7 seg 2 (HEX2)
	output wire [6:0]  HEX3,             // Segmentos do display de 7 seg 3 (HEX3)
	output wire [6:0]  HEX4,             // Segmentos do display de 7 seg 4 (HEX4)
	output wire [6:0]  HEX5,             // Segmentos do display de 7 seg 5 (HEX5)

	// Conexoes do DAC de Video VGA (ADV7123)
	output wire [7:0]  VGA_R,            // Canal de cor Vermelho de 8 bits (VGA_R)
	output wire [7:0]  VGA_G,            // Canal de cor Verde de 8 bits (VGA_G)
	output wire [7:0]  VGA_B,            // Canal de cor Azul de 8 bits (VGA_B)
	output wire        VGA_HS,           // Pulso de Sincronismo Horizontal (VGA_HS)
	output wire        VGA_VS,           // Pulso de Sincronismo Vertical (VGA_VS)
	output wire        VGA_CLK,          // Clock sincrono do pixel de 25 MHz (VGA_CLK)
	output wire        VGA_BLANK_N,      // Sinalizador de area ativa de video (VGA_BLANK_N)
	output wire        VGA_SYNC_N        // Sinalizador de sincronismo no Verde (VGA_SYNC_N)
);

	// Mapeamento dos pinos maiusculos da placa para os nomes internos do projeto
	wire        clock_50mhz = CLOCK_50;
	wire [3:0]  key_n       = KEY;

	// Barramentos de sinal para feedbacks e barramento de exibicao interna
	wire [9:0]  ledr;
	wire [6:0]  hex0;
	wire [6:0]  hex1;
	wire [6:0]  hex2;
	wire [6:0]  hex3;
	wire [6:0]  hex4;
	wire [6:0]  hex5;

	// Barramentos internos para conector VGA
	wire [7:0]  vga_r;
	wire [7:0]  vga_g;
	wire [7:0]  vga_b;
	wire        vga_hs;
	wire        vga_vs;
	wire        vga_clock;
	wire        vga_blank_n;
	wire        vga_sync_n;

	// Associacao sincrona dos barramentos internos as portas fisicas maiusculas de saida
	assign LEDR        = ledr;
	assign HEX0        = hex0;
	assign HEX1        = hex1;
	assign HEX2        = hex2;
	assign HEX3        = hex3;
	assign HEX4        = hex4;
	assign HEX5        = hex5;

	assign VGA_R       = vga_r;
	assign VGA_G       = vga_g;
	assign VGA_B       = vga_b;
	assign VGA_HS      = vga_hs;
	assign VGA_VS      = vga_vs;
	assign VGA_CLK     = vga_clock;
	assign VGA_BLANK_N = vga_blank_n;
	assign VGA_SYNC_N  = vga_sync_n;

	// Sinais de clock e reset internos sincronizados
	wire clock_vga;          // Clock de pixel de 25 MHz para VGA
	wire reset_vga_n;        // Reset sincrono ativo em nivel baixo (KEY0)

	// Divisor de clock e sincronizador de reset
 clock_reset divisor_clock (
	   .CLOCK_50  (clock_50mhz),
 	   .reset_n   (key_n[0] & HPS_RESET_N),
	   .vga_clk   (clock_vga),
	   .vga_rst_n (reset_vga_n)
	);
    
    assign vga_clock = clock_vga;

   // Coordenadas fisicas da varredura VGA e sinal de apagamento
   wire [9:0] coord_x_vga;   // Coluna de pixel na tela (0 a 639)
   wire [9:0] coord_y_vga;   // Linha de pixel na tela (0 a 479)
   wire       area_visivel;   // Sinal de blanking (1 = desenhando, 0 = apagamento)
   wire       inicio_vblank;

   // Gerador de sincronismo VGA de 640x480 @ 60Hz
   controlador_vga gerador_sincronismo (
      .vga_clk   (clock_vga),
      .vga_rst_n (reset_vga_n),
      .o_hsync   (vga_hs),
      .o_vsync   (vga_vs),
      .o_blank_n (area_visivel),
      .o_inicio_vblank(inicio_vblank),
      .o_x       (coord_x_vga),
      .o_y       (coord_y_vga)
   );
    
   assign vga_blank_n = area_visivel;
   assign vga_sync_n   = 1'b1; // Inativo para monitores comuns

   // Resolucao logica: conversao de 640x480 para 320x240
   // O pixel logico e ampliado por um fator 2x2. Uma divisao por 2 equivale a deslocar 1 bit.
   wire [8:0] coord_logica_x = coord_x_vga[9:1]; // Posicao logica horizontal (0-319)
   wire [7:0] coord_logica_y = coord_y_vga[9:1]; // Posicao logica vertical (0-239)

   // Os controles de desenho fisicos foram removidos: chaves/botoes nao
   // comandam motores. KEY0 permanece somente como reset global da placa.
   wire [1:0] estado_atual_fsm = 2'b00;

   // Declara os barramentos de debug do rasterizador com suas larguras.
   wire [8:0] cursor_x_debug;
   wire [7:0] cursor_y_debug;
   wire [1:0] captura_poligono_debug;

   // Barramentos de cor de 8 bits gerados por cada motor grafico
   wire [7:0] cor_fundo;
   wire [7:0] cor_sprite;
   wire [7:0] cor_poligono;

   // Sinais de escrita do tilemap vindos do decodificador de comandos.
   wire        tile_wr_en;
   wire [5:0]  tile_wr_x;
   wire [4:0]  tile_wr_y;
   wire [7:0]  tile_wr_cor;

   // Scroll comandado pela mesma unidade que trata sprites e tiles.
   wire        scroll_atualizar;
   wire [1:0]  scroll_direcao;
   wire [3:0]  scroll_quantidade;

   // Triangulo enviado pelo ARM em tres comandos de 32 bits.
   wire        tri_desenhar;
   wire [8:0]  tri_x1, tri_x2, tri_x3;
   wire [7:0]  tri_y1, tri_y2, tri_y3, tri_cor;

   // Retangulo/quadrado enviado pelo ARM em duas palavras de 32 bits.
   wire        ret_desenhar;
   wire [8:0]  ret_x1, ret_x2;
   wire [7:0]  ret_y1, ret_y2, ret_cor;

   // Motor de plano de fundo (background)
   motor_background motor_background (
      .clk       (clock_vga),
      .reset_n   (reset_vga_n),
      .x_logico  (coord_logica_x),
      .y_logico  (coord_logica_y),
      .tile_wr_en (tile_wr_en),
      .tile_wr_x  (tile_wr_x),
      .tile_wr_y  (tile_wr_y),
      .tile_wr_cor(tile_wr_cor),
      .scroll_atualizar (scroll_atualizar),
      .scroll_direcao   (scroll_direcao),
      .scroll_quantidade(scroll_quantidade),
      .indice_cor(cor_fundo)
   );

   // Caminho passivo: PIOs do HPS -> FIFO/IR -> UC unica -> motores.
   wire [31:0] ir;
   wire        instr_valid, uc_busy, uc_done, uc_invalida;
   wire fila_ack, fila_ready, fila_busy, fila_done, fila_erro;
   wire [3:0] fila_quantidade;

   wire [2:0]  sprite_movimento_isa;
   wire [8:0]  sprite_atributos_isa;

   wire [8:0] sprite_x_debug;
   wire [7:0] sprite_y_debug;
   wire       sprite_pixel_valido;
   wire [4:0] sprite_id_debug;
   wire       sprite_direcao_debug;

   fila_comandos fila (
      .clk(clock_vga), .reset_n(reset_vga_n),
      .mmio_comando(GPU_CMD), .mmio_req(GPU_REQ), .ack(fila_ack),
      .ready(fila_ready), .uc_busy(uc_busy), .uc_done(uc_done),
      .uc_invalida(uc_invalida), .erro(fila_erro),
      .ir(ir), .instr_valid(instr_valid),
      .busy(fila_busy), .done(fila_done), .quantidade(fila_quantidade)
   );

   // Registrador dedicado de status. Bits 4..0: DONE, BUSY, READY, ERRO, ACK.
   // A assinatura 0x4750 permite ao programa HPS validar o hardware.
   reg [31:0] status_reg;
   assign GPU_STATUS = status_reg;
   always @(posedge clock_vga or negedge reset_vga_n) begin
      if (!reset_vga_n)
         status_reg <= {16'h4750, 11'd0, 5'b00101};
      else
         status_reg <= {16'h4750, 11'd0, fila_done, fila_busy,
                        fila_ready, fila_erro, fila_ack};
   end

   unidade_controle uc_sprites (
      .clk                (clock_vga),
      .reset_n            (reset_vga_n),
      .instr_valid        (instr_valid),
      .instr              (ir),
      .inicio_vblank      (inicio_vblank),
      .busy               (uc_busy),
      .done               (uc_done),
      .instr_invalida     (uc_invalida),
      .sprite_movimento_isa(sprite_movimento_isa),
      .sprite_atributos_isa(sprite_atributos_isa),
      .tile_wr_en         (tile_wr_en),
      .tile_wr_x          (tile_wr_x),
      .tile_wr_y          (tile_wr_y),
      .tile_wr_cor        (tile_wr_cor),
      .scroll_atualizar  (scroll_atualizar),
      .scroll_direcao    (scroll_direcao),
      .scroll_quantidade(scroll_quantidade),
      .tri_desenhar      (tri_desenhar),
      .tri_x1            (tri_x1),
      .tri_y1            (tri_y1),
      .tri_x2            (tri_x2),
      .tri_y2            (tri_y2),
      .tri_x3            (tri_x3),
      .tri_y3            (tri_y3),
      .tri_cor           (tri_cor),
      .ret_desenhar      (ret_desenhar),
      .ret_x1            (ret_x1),
      .ret_y1            (ret_y1),
      .ret_x2            (ret_x2),
      .ret_y2            (ret_y2),
      .ret_cor           (ret_cor),
      .sprite_x_atual     (sprite_x_debug),
      .sprite_y_atual     (sprite_y_debug),
      .modo_direcao_atual (sprite_direcao_debug)
   );

   motor_sprites motor_sprites (
      .clk            (clock_vga),
      .reset_n        (reset_vga_n),
      .x_logico       (coord_logica_x),
      .y_logico       (coord_logica_y),
      .movimento_isa  (sprite_movimento_isa),
      .atributos_isa  (sprite_atributos_isa),
      .pixel_valido   (sprite_pixel_valido),
      .indice_cor     (cor_sprite),
      .sprite_x_debug (sprite_x_debug),
      .sprite_y_debug (sprite_y_debug),
      .sprite_id_debug(sprite_id_debug),
      .direcao_debug  (sprite_direcao_debug)
   );

   // Rasterizador comandado exclusivamente pelas instrucoes de poligono.
   rasterizador_poligonos rasterizador_poligonos (
      .clk       (clock_vga),
      .reset_n   (reset_vga_n),
      .x_logico  (coord_logica_x),
      .y_logico  (coord_logica_y),
      .triangulo_desenhar(tri_desenhar),
      .tri_x1    (tri_x1), .tri_y1(tri_y1),
      .tri_x2    (tri_x2), .tri_y2(tri_y2),
      .tri_x3    (tri_x3), .tri_y3(tri_y3),
      .tri_cor   (tri_cor),
      .retangulo_desenhar(ret_desenhar),
      .ret_x1    (ret_x1), .ret_y1(ret_y1),
      .ret_x2    (ret_x2), .ret_y2(ret_y2),
      .ret_cor   (ret_cor),
      .indice_cor(cor_poligono),
      .cursor_x_debug(cursor_x_debug),
      .cursor_y_debug(cursor_y_debug),
      .estado_debug(captura_poligono_debug)
    );

   // Compositor de Video: define a prioridade de sobreposicao de cada plano
   wire [7:0] cor_pixel_final;

   compositor compositor_de_video (
      .cor_bg    (cor_fundo),
      .cor_spr   (cor_sprite),
      .spr_valido(sprite_pixel_valido),
      .cor_poly  (cor_poligono),
      .cor_final (cor_pixel_final)
   );

   // Paleta de Cores: converte indice de 8 bits para RGB de 24 bits
   wire [23:0] rgb_final;

   ram_paleta memoria_paleta (
      .clock     (clock_vga),
      .address   (cor_pixel_final),
      .q         (rgb_final)
   );

   // Envio dos sinais de cores filtrados pela visibilidade da tela
   assign vga_r = (area_visivel) ? rgb_final[23:16] : 8'd0;
   assign vga_g = (area_visivel) ? rgb_final[15:8]  : 8'd0;
   assign vga_b = (area_visivel) ? rgb_final[7:0]   : 8'd0;

   // LED9 READY, LED8 BUSY, LED7 DONE, LED6 ERRO,
   // LED5 cheia, LED4 ACK, LED3..0 quantidade na FIFO.
   assign ledr = {fila_ready, fila_busy, fila_done, fila_erro,
                  !fila_ready, fila_ack, fila_quantidade};

   // Displays de depuracao: X/Y do sprite atualmente selecionado.
   reg [8:0] display_x;
   reg [7:0] display_y;

   always @(*) begin
      display_x = sprite_x_debug;
      display_y = sprite_y_debug;
   end

   decodificador_hex decodificador_hex0 (
      .dado_entrada(display_x[3:0]),
      .saida_hex   (hex0)
   );
	
   decodificador_hex decodificador_hex1 (
      .dado_entrada(display_x[7:4]),
      .saida_hex   (hex1)
   );
	
   decodificador_hex decodificador_hex2 (
      .dado_entrada({3'd0, display_x[8]}),
      .saida_hex   (hex2)
   );
	
   decodificador_hex decodificador_hex3 (
      .dado_entrada(display_y[3:0]),
      .saida_hex   (hex3)
   );
	
   decodificador_hex decodificador_hex4 (
      .dado_entrada(display_y[7:4]),
      .saida_hex   (hex4)
   );
	 
   decodificador_hex decodificador_hex5 (
      .dado_entrada({2'b0, estado_atual_fsm}),
      .saida_hex   (hex5)
   );

endmodule
