// Datapath explicito: banco de registradores para operandos da ISA e duas
// operacoes da ULA para comparar X/Y atual do sprite com o alvo.
module datapath_grafico (
    input wire clk,
    input wire reset_n,
    input wire reg_write,
    input wire [2:0] reg_addr,
    input wire [31:0] reg_data,
    output wire [31:0] r0, r1, r2, r3, r4, r5, r6, r7,
    input wire [8:0] sprite_x,
    input wire [8:0] alvo_x,
    input wire [7:0] sprite_y,
    input wire [7:0] alvo_y,
    output wire x_menor, x_maior, y_menor, y_maior
);
    wire [31:0] resultado_x, resultado_y;
    wire zero_x, zero_y, menor_x, menor_y;

    banco_registradores_graficos banco (
        .clk(clk), .reset_n(reset_n), .write_enable(reg_write),
        .write_addr(reg_addr), .write_data(reg_data),
        .r0(r0), .r1(r1), .r2(r2), .r3(r3),
        .r4(r4), .r5(r5), .r6(r6), .r7(r7)
    );

    ula_grafica ula_x (
        .operando_a({23'd0, sprite_x}), .operando_b({23'd0, alvo_x}),
        .operacao(2'b01), .resultado(resultado_x), .zero(zero_x), .menor(menor_x)
    );
    ula_grafica ula_y (
        .operando_a({24'd0, sprite_y}), .operando_b({24'd0, alvo_y}),
        .operacao(2'b01), .resultado(resultado_y), .zero(zero_y), .menor(menor_y)
    );

    assign x_menor = menor_x;
    assign x_maior = !menor_x && !zero_x;
    assign y_menor = menor_y;
    assign y_maior = !menor_y && !zero_y;
endmodule
