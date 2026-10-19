// motor_background.v
// Plano de fundo baseado em tilemap 40 x 30 (tiles de 8 x 8 pixels).
//
// Usa a mapa_ram existente (1200 x 8, init = background_map.mif).
// Cada palavra guarda a cor RGB332 do tile. A escrita pelo HPS e preservada.
// A memoria e a paleta nao sao substituidas nesta atualizacao.
//
// O scroll e alterado somente por instrucoes recebidas da unidade de controle.
//
// Fluxo:
//   x/y logico -> tile da tela (x>>3, y>>3) + scroll_tile (mod 40 / mod 30)
//              -> endereco = tile_y*40 + tile_x -> mapa_ram -> indice_cor
//
// A leitura sincrona da mapa_ram existente e preservada.

module motor_background (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [8:0]  x_logico,        // 0..319
    input  wire [7:0]  y_logico,        // 0..239
    // Comando da UC unica: direcao da camera e quantidade 1..15 tiles.
    input  wire        scroll_atualizar,
    input  wire [1:0]  scroll_direcao,
    input  wire [3:0]  scroll_quantidade,

    // Escrita do tilemap pelo HPS (um tile = um bloco 8x8 de uma cor RGB332).
    input  wire        tile_wr_en,
    input  wire [5:0]  tile_wr_x,       // 0..39
    input  wire [4:0]  tile_wr_y,       // 0..29
    input  wire [7:0]  tile_wr_cor,     // RGB332

    output wire [7:0]  indice_cor
);

    localparam TILES_X = 6'd40;
    localparam TILES_Y = 5'd30;

    // ============================================================
    // SCROLL EM TILES
    // ============================================================
    reg [5:0] scroll_tile_x;   // 0..39
    reg [4:0] scroll_tile_y;   // 0..29

    // A quantidade maxima e 15. Uma unica correcao basta para o wrap.
    // As somas sao alargadas para nao perder o carry antes da comparacao.
    wire [6:0] scroll_soma_x = {1'b0, scroll_tile_x} +
                               {3'd0, scroll_quantidade};
    wire [5:0] scroll_soma_y = {1'b0, scroll_tile_y} +
                               {2'd0, scroll_quantidade};
    wire [6:0] scroll_sub_x = {1'b0, scroll_tile_x} + 7'd40 -
                              {3'd0, scroll_quantidade};
    wire [5:0] scroll_sub_y = {1'b0, scroll_tile_y} + 6'd30 -
                              {2'd0, scroll_quantidade};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            scroll_tile_x <= 6'd0;
            scroll_tile_y <= 5'd0;
        end
        else if (scroll_atualizar) begin
            case (scroll_direcao)
                2'b00: begin // camera para a direita
                    if (scroll_soma_x >= 7'd40)
                        scroll_tile_x <= scroll_soma_x - 7'd40;
                    else
                        scroll_tile_x <= scroll_soma_x[5:0];
                end
                2'b01: begin // camera para a esquerda
                    if (scroll_tile_x < {2'd0, scroll_quantidade})
                        scroll_tile_x <= scroll_sub_x[5:0];
                    else
                        scroll_tile_x <= scroll_tile_x - {2'd0, scroll_quantidade};
                end
                2'b10: begin // camera para cima
                    if (scroll_tile_y < {1'b0, scroll_quantidade})
                        scroll_tile_y <= scroll_sub_y[4:0];
                    else
                        scroll_tile_y <= scroll_tile_y - {1'b0, scroll_quantidade};
                end
                2'b11: begin // camera para baixo
                    if (scroll_soma_y >= 6'd30)
                        scroll_tile_y <= scroll_soma_y - 6'd30;
                    else
                        scroll_tile_y <= scroll_soma_y[4:0];
                end
            endcase
        end
    end

    // ============================================================
    // TILE DA TELA + SCROLL (COM WRAP)
    // ============================================================
    // Como o scroll e em tiles inteiros, nao ha soma em pixels:
    // basta somar o scroll ao indice do tile da tela.
    wire [5:0] tela_tile_x = x_logico[8:3];   // 0..39
    wire [4:0] tela_tile_y = y_logico[7:3];   // 0..29

    wire [6:0] soma_x = {1'b0, tela_tile_x} + {1'b0, scroll_tile_x};  // 0..78
    wire [5:0] soma_y = {1'b0, tela_tile_y} + {1'b0, scroll_tile_y};  // 0..58

    wire [5:0] tile_x = (soma_x >= {1'b0, TILES_X}) ? (soma_x - {1'b0, TILES_X}) : soma_x[5:0];
    wire [4:0] tile_y = (soma_y >= {1'b0, TILES_Y}) ? (soma_y - {1'b0, TILES_Y}) : soma_y[4:0];

    // endereco = tile_y * 40 + tile_x   (40 = 32 + 8)
    wire [10:0] linha_x40     = ({6'd0, tile_y} << 5) + ({6'd0, tile_y} << 3);
    wire [10:0] endereco_mapa = linha_x40 + {5'd0, tile_x};

    // ============================================================
    // MAPA_RAM: leitura para o VGA + escrita pelo HPS
    // endereco de escrita = tile_wr_y * 40 + tile_wr_x
    // ============================================================
    wire [10:0] wr_linha_x40 = ({6'd0, tile_wr_y} << 5) +
                                ({6'd0, tile_wr_y} << 3);
    wire [10:0] endereco_escrita = wr_linha_x40 + {5'd0, tile_wr_x};

    // Protecao simples: ignora coordenadas fora do tilemap 40x30.
    wire escrita_valida = tile_wr_en &&
                          (tile_wr_x < 6'd40) &&
                          (tile_wr_y < 5'd30);

    mapa_ram RAM_MAPA (
        .clock      (clk),
        .rdaddress  (endereco_mapa),
        .wraddress  (endereco_escrita),
        .data       (tile_wr_cor),
        .wren       (escrita_valida),
        .q          (indice_cor)
    );

endmodule
