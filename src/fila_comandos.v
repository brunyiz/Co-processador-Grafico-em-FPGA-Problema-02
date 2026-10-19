// Busca passiva: recebe palavras do HPS; nao possui PC nem ROM de instrucoes.
// FIFO de 8 palavras, mais um IR para a instrucao em execucao.
// HPS escreve CMD, alterna REQ e mantem CMD estavel ate ACK == REQ.
// ACK confirma ENTRADA na fila. DONE indica fila + executor ociosos.
module fila_comandos (
    input wire clk, reset_n,
    input wire [31:0] mmio_comando,
    input wire mmio_req,
    output reg ack,
    output wire ready,
    input wire uc_busy, uc_done, uc_invalida,
    output reg [31:0] ir,
    output reg instr_valid,
    output wire busy, done,
    output reg erro,
    output reg [3:0] quantidade
);
    reg [31:0] memoria [0:7];
    reg [2:0] escrita, leitura;
    reg em_execucao;

    // PIOs trabalham a 50 MHz; fila e UC trabalham a 25 MHz.
    // O protocolo mantem a palavra estavel durante sua captura.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg req_s1, req_s2;
    reg [31:0] cmd_s1, cmd_s2;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            req_s1 <= 0; req_s2 <= 0;
            cmd_s1 <= 0; cmd_s2 <= 0;
        end else begin
            req_s1 <= mmio_req; req_s2 <= req_s1;
            cmd_s1 <= mmio_comando; cmd_s2 <= cmd_s1;
        end
    end

    wire inserir = (req_s2 != ack) && ready;
    wire retirar = (quantidade != 0) && !em_execucao && !uc_busy;
    assign ready = quantidade < 4'd8;
    assign busy = em_execucao || (quantidade != 0) || uc_busy;
    assign done = !busy;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            escrita <= 0; leitura <= 0; quantidade <= 0;
            ir <= 0; instr_valid <= 0; em_execucao <= 0;
            ack <= 0; erro <= 0;
        end else begin
            instr_valid <= 0;
            if (inserir) begin
                memoria[escrita] <= cmd_s2;
                escrita <= escrita + 3'd1;
                ack <= req_s2; // confirma somente depois de guardar
                if (!busy) erro <= 0; // inicio de um novo lote
            end
            if (retirar) begin
                ir <= memoria[leitura];
                leitura <= leitura + 3'd1;
                instr_valid <= 1;
                em_execucao <= 1;
            end
            if (em_execucao && uc_done) begin
                em_execucao <= 0;
                if (uc_invalida) erro <= 1;
            end
            case ({inserir, retirar})
                2'b10: quantidade <= quantidade + 4'd1;
                2'b01: quantidade <= quantidade - 4'd1;
                default: quantidade <= quantidade;
            endcase
        end
    end
endmodule
