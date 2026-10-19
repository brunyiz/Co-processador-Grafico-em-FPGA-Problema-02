// Rasterizador de triangulos e retangulos recebidos exclusivamente pela ISA.
module rasterizador_poligonos (
   input  wire        clk,
   input  wire        reset_n,
   input  wire [8:0]  x_logico,
   input  wire [7:0]  y_logico,
   input  wire        triangulo_desenhar,
   input  wire [8:0]  tri_x1, tri_x2, tri_x3,
   input  wire [7:0]  tri_y1, tri_y2, tri_y3,
   input  wire [7:0]  tri_cor,
   input  wire        retangulo_desenhar,
   input  wire [8:0]  ret_x1, ret_x2,
   input  wire [7:0]  ret_y1, ret_y2,
   input  wire [7:0]  ret_cor,
   output reg  [7:0]  indice_cor,
   output wire [8:0]  cursor_x_debug,
   output wire [7:0]  cursor_y_debug,
   output wire [1:0]  estado_debug
);
   reg [8:0] X1, X2, X3;
   reg [7:0] Y1, Y2, Y3;
   reg tipo_latched;
   reg poligono_valido;
   reg [7:0] cor_latched;

   // Portas antigas de depuracao mantidas para compatibilidade do top-level.
   assign cursor_x_debug = 9'd0;
   assign cursor_y_debug = 8'd0;
   assign estado_debug = 2'd0;

   always @(posedge clk or negedge reset_n) begin
      if (!reset_n) begin
         X1 <= 9'd0; Y1 <= 8'd0; X2 <= 9'd0; Y2 <= 8'd0;
         X3 <= 9'd0; Y3 <= 8'd0;
         tipo_latched <= 1'b0;
         poligono_valido <= 1'b0;
         cor_latched <= 8'd0;
      end else if (triangulo_desenhar) begin
         X1 <= tri_x1; Y1 <= tri_y1;
         X2 <= tri_x2; Y2 <= tri_y2;
         X3 <= tri_x3; Y3 <= tri_y3;
         cor_latched <= tri_cor;
         tipo_latched <= 1'b0;
         poligono_valido <= 1'b1;
      end else if (retangulo_desenhar) begin
         X1 <= ret_x1; Y1 <= ret_y1;
         X2 <= ret_x2; Y2 <= ret_y2;
         cor_latched <= ret_cor;
         tipo_latched <= 1'b1;
         poligono_valido <= 1'b1;
      end
   end

   wire [8:0] min_x = (X1 < X2) ? X1 : X2;
   wire [8:0] max_x = (X1 > X2) ? X1 : X2;
   wire [7:0] min_y = (Y1 < Y2) ? Y1 : Y2;
   wire [7:0] max_y = (Y1 > Y2) ? Y1 : Y2;
   wire pixel_no_retangulo =
      (x_logico >= min_x) && (x_logico <= max_x) &&
      (y_logico >= min_y) && (y_logico <= max_y);

   // Testes de aresta assinados para rasterizar o triangulo preenchido.
   wire signed [10:0] px_x1 = $signed({1'b0,x_logico}) - $signed({1'b0,X1});
   wire signed [10:0] px_x2 = $signed({1'b0,x_logico}) - $signed({1'b0,X2});
   wire signed [10:0] px_x3 = $signed({1'b0,x_logico}) - $signed({1'b0,X3});
   wire signed [9:0] py_y1 = $signed({1'b0,y_logico}) - $signed({1'b0,Y1});
   wire signed [9:0] py_y2 = $signed({1'b0,y_logico}) - $signed({1'b0,Y2});
   wire signed [9:0] py_y3 = $signed({1'b0,y_logico}) - $signed({1'b0,Y3});
   wire signed [9:0] dy12 = $signed({1'b0,Y2}) - $signed({1'b0,Y1});
   wire signed [9:0] dy23 = $signed({1'b0,Y3}) - $signed({1'b0,Y2});
   wire signed [9:0] dy31 = $signed({1'b0,Y1}) - $signed({1'b0,Y3});
   wire signed [10:0] dx12 = $signed({1'b0,X2}) - $signed({1'b0,X1});
   wire signed [10:0] dx23 = $signed({1'b0,X3}) - $signed({1'b0,X2});
   wire signed [10:0] dx31 = $signed({1'b0,X1}) - $signed({1'b0,X3});
   wire signed [21:0] e12 = px_x1 * dy12 - py_y1 * dx12;
   wire signed [21:0] e23 = px_x2 * dy23 - py_y2 * dx23;
   wire signed [21:0] e31 = px_x3 * dy31 - py_y3 * dx31;
   wire todos_positivos = (e12 >= 0) && (e23 >= 0) && (e31 >= 0);
   wire todos_negativos = (e12 <= 0) && (e23 <= 0) && (e31 <= 0);
   wire pixel_no_triangulo = todos_positivos || todos_negativos;

   always @(*) begin
      if (!poligono_valido)
         indice_cor = 8'd0;
      else if (tipo_latched)
         indice_cor = pixel_no_retangulo ? cor_latched : 8'd0;
      else
         indice_cor = pixel_no_triangulo ? cor_latched : 8'd0;
   end
endmodule
