// compositor.v
// Responsável por combinar as três camadas de vídeo (background, sprites e polígonos)
// aplicando as regras de prioridade e transparência (índice de cor 0 é transparente).

module compositor (
   input  wire [7:0] cor_bg,    // Índice de cor vindo do motor de background
   input  wire [7:0] cor_spr,   // Índice de cor vindo do motor de sprites
   input  wire       spr_valido,// 1 quando o pixel do sprite deve cobrir as camadas inferiores
   input  wire [7:0] cor_poly,  // Índice de cor vindo do rasterizador de polígonos
   output reg  [7:0] cor_final  // Índice de cor final a ser enviado para a RAM de paleta
);

   // Regra de Prioridade: Sprites > Polígonos > Background
   // O índice de cor 8'h00 (0) é reservado para transparência em sprites e polígonos.
	
   always @(*) begin
      if (spr_valido) begin
         cor_final = cor_spr;   // Prioridade máxima os sprites ativos
      end else if (cor_poly != 8'd0) begin
         cor_final = cor_poly;    // Prioridade média para polígonos rasterizados
      end else begin
         cor_final = cor_bg;     // Prioridade mínima (fundo sempre visível por padrão)
      end
   end

endmodule
