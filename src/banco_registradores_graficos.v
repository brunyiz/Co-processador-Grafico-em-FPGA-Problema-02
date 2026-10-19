// Banco pequeno de registradores da ISA grafica.
// r0..r2: vertices do triangulo; r3: cor do triangulo.
// r4..r5: pontos do retangulo; r6: cor do retangulo.
module banco_registradores_graficos (
    input wire clk,
    input wire reset_n,
    input wire write_enable,
    input wire [2:0] write_addr,
    input wire [31:0] write_data,
    output reg [31:0] r0, r1, r2, r3, r4, r5, r6, r7
);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r0 <= 32'd0; r1 <= 32'd0; r2 <= 32'd0; r3 <= 32'd0;
            r4 <= 32'd0; r5 <= 32'd0; r6 <= 32'd0; r7 <= 32'd0;
        end else if (write_enable) begin
            case (write_addr)
                3'd0: r0 <= write_data;
                3'd1: r1 <= write_data;
                3'd2: r2 <= write_data;
                3'd3: r3 <= write_data;
                3'd4: r4 <= write_data;
                3'd5: r5 <= write_data;
                3'd6: r6 <= write_data;
                3'd7: r7 <= write_data;
            endcase
        end
    end
endmodule
