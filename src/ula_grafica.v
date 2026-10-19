// ULA combinacional usada pelo datapath para comparar a posicao do sprite
// com o alvo recebido na instrucao. OP=00 soma; OP=01 subtrai/compara.
module ula_grafica (
    input wire [31:0] operando_a,
    input wire [31:0] operando_b,
    input wire [1:0] operacao,
    output reg [31:0] resultado,
    output wire zero,
    output wire menor
);
    always @(*) begin
        case (operacao)
            2'b00: resultado = operando_a + operando_b;
            2'b01: resultado = operando_a - operando_b;
            2'b10: resultado = operando_a & operando_b;
            default: resultado = operando_a | operando_b;
        endcase
    end
    assign zero = (resultado == 32'd0);
    assign menor = (operando_a < operando_b);
endmodule
