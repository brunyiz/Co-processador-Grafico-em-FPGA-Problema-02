// controlador_vga.v
// Gera os sinais de sincronismo horizontal e vertical para resolução de 640x480 @ 60Hz.
// Fornece as coordenadas físicas X (0-639) e Y (0-479) para a varredura da tela.

module controlador_vga (
   input  wire       vga_clk,       // Clock de pixel de 25 MHz
   input  wire       vga_rst_n,     // Reset ativo em nível baixo
   output reg        o_hsync,       // Pulso de sincronismo horizontal (ativo em baixo)
   output reg        o_vsync,       // Pulso de sincronismo vertical (ativo em baixo)
   output reg        o_blank_n,     // Área ativa de vídeo (1 = visível, 0 = apagamento)
   output reg        o_inicio_vblank, // Pulso de 1 clock no inicio do VBlank
   output wire [9:0] o_x,           // Coordenada física horizontal do pixel
   output wire [9:0] o_y            // Coordenada física vertical do pixel
);

   // Definição dos tempos da temporização horizontal (em pixels/clocks)
   parameter H_ATIVO      = 10'd640; // Largura visível
   parameter H_FRONT_PORCH = 10'd16;  // Margem frontal
   parameter H_SYNC_PULSE = 10'd96;  // Largura do pulso de sincronismo
   parameter H_BACK_PORCH  = 10'd48;  // Margem traseira
   parameter H_TOTAL       = 10'd800; // Total de pixels por linha (640+16+96+48)

   // Definição dos tempos da temporização vertical (em linhas)
   parameter V_ATIVO      = 10'd480; // Altura visível
   parameter V_FRONT_PORCH = 10'd10;  // Margem superior
   parameter V_SYNC_PULSE = 10'd2;   // Altura do pulso de sincronismo
   parameter V_BACK_PORCH  = 10'd33;  // Margem inferior
   parameter V_TOTAL       = 10'd525; // Total de linhas por quadro (480+10+2+33)

   // Contadores internos de varredura de pixel e linha
   reg [9:0] contador_h; // Contador horizontal (0 a 799)
   reg [9:0] contador_v; // Contador vertical (0 a 524)

   // Lógica do Contador Horizontal
   always @(posedge vga_clk or negedge vga_rst_n) begin
      if (!vga_rst_n) begin
         contador_h <= 10'd0;
      end else begin
         if (contador_h == (H_TOTAL - 10'd1)) begin
            contador_h <= 10'd0;
         end else begin
            contador_h <= contador_h + 10'd1;
         end
      end
   end

   // Lógica do Contador Vertical
   always @(posedge vga_clk or negedge vga_rst_n) begin
      if (!vga_rst_n) begin
         contador_v <= 10'd0;
      end else begin
         if (contador_h == (H_TOTAL - 10'd1)) begin
            if (contador_v == (V_TOTAL - 10'd1)) begin
               contador_v <= 10'd0;
            end else begin
               contador_v <= contador_v + 10'd1;
            end
         end
      end
   end

   // Geração dos Sinais de Sincronismo e Área Visível (Registrados para evitar glitches)
   always @(posedge vga_clk or negedge vga_rst_n) begin
      if (!vga_rst_n) begin
         o_hsync   <= 1'b1;
         o_vsync   <= 1'b1;
         o_blank_n <= 1'b0;
         o_inicio_vblank <= 1'b0;
      end else begin
         o_inicio_vblank <= 1'b0;
         if ((contador_h == 10'd0) && (contador_v == V_ATIVO))
            o_inicio_vblank <= 1'b1;
         // HSYNC ativo em baixo durante a janela do pulso de sincronismo horizontal
         if ((contador_h >= (H_ATIVO + H_FRONT_PORCH)) && 
            (contador_h < (H_ATIVO + H_FRONT_PORCH + H_SYNC_PULSE))) begin
            o_hsync <= 1'b0;
         end else begin
            o_hsync <= 1'b1;
         end

         // VSYNC ativo em baixo durante a janela do pulso de sincronismo vertical
         if ((contador_v >= (V_ATIVO + V_FRONT_PORCH)) && 
            (contador_v < (V_ATIVO + V_FRONT_PORCH + V_SYNC_PULSE))) begin
            o_vsync <= 1'b0;
         end else begin
            o_vsync <= 1'b1;
         end

         // BLANK_N em nível alto apenas se estivermos na área visível da tela (desenhando)
         if ((contador_h < H_ATIVO) && (contador_v < V_ATIVO)) begin
            o_blank_n <= 1'b1;
         end else begin
            o_blank_n <= 1'b0;
         end
      end
   end

   // As coordenadas de saída são limitadas à área ativa para segurança.
   assign o_x = (contador_h < H_ATIVO) ? contador_h : (H_ATIVO - 10'd2);
   assign o_y = (contador_v < V_ATIVO) ? contador_v : (V_ATIVO - 10'd1);

endmodule
