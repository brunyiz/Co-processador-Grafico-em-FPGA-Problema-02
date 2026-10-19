#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* API exportada pelo driver. */
int gpu_init(void);
void gpu_close(void);
uint32_t gpu_status(void);
int gpu_send_scroll(unsigned direcao, unsigned tiles);
int gpu_send_tile(unsigned x, unsigned y, unsigned cor);
int gpu_send_sprite(unsigned id, unsigned x, unsigned y, unsigned visivel,
                    unsigned espelho, unsigned transparente);
int gpu_send_vsync(void);
int gpu_send_triangle(unsigned x1, unsigned y1, unsigned x2, unsigned y2,
                      unsigned x3, unsigned y3, unsigned cor);
int gpu_send_rectangle(unsigned x1, unsigned y1, unsigned x2, unsigned y2,
                       unsigned cor);
int gpu_wait_done(void);

#define ACK   (1U << 0)
#define ERRO  (1U << 1)
#define READY (1U << 2)
#define BUSY  (1U << 3)
#define DONE  (1U << 4)

static int ler_linha(char *linha, size_t tamanho) {
    if (!fgets(linha, (int)tamanho, stdin)) return 0;
    linha[strcspn(linha, "\n")] = '\0';
    return 1;
}

static void mostrar_estado(void) {
    uint32_t s = gpu_status();
    printf("STATUS=0x%08X READY=%u BUSY=%u DONE=%u ERRO=%u ACK=%u\n",
           (unsigned)s, !!(s & READY), !!(s & BUSY), !!(s & DONE),
           !!(s & ERRO), !!(s & ACK));
}

static void mostrar_cores(void) {
    puts("Cores RGB332: 00 preto, E0 vermelho, 1C verde, 03 azul,");
    puts("             FF branco, FC amarelo, 1F ciano, E3 magenta.");
}

static int terminar_comando(int resultado) {
    if (resultado != 0) {
        perror("Comando grafico");
        mostrar_estado();
        return -1;
    }
    if (gpu_wait_done() != 0) {
        perror("Aguardar conclusao");
        mostrar_estado();
        return -1;
    }
    mostrar_estado();
    return 0;
}

int main(void) {
    char linha[128];
    int opcao;

    if (gpu_init() != 0) {
        perror("Inicializar driver da GPU (execute com sudo)");
        return 1;
    }

    puts("Coprocessador conectado. Coloque SW9=0 e SW8=1 na placa.");
    mostrar_estado();

    for (;;) {
        puts("\n1 - Mostrar tres sprites de exemplo");
        puts("2 - Posicionar/configurar um sprite");
        puts("3 - Mostrar status READY/BUSY/DONE");
        puts("4 - Alterar a cor de um tile");
        puts("5 - Scroll do background");
        puts("6 - Desenhar triangulo preenchido");
        puts("7 - Desenhar retangulo/quadrado por dois pontos");
        puts("8 - Aguardar VBlank (VSYNC)");
        puts("0 - Sair");
        printf("Opcao: "); fflush(stdout);
        if (!ler_linha(linha, sizeof linha)) break;
        if (sscanf(linha, "%d", &opcao) != 1) continue;
        if (opcao == 0) break;
        if (opcao == 3) { mostrar_estado(); continue; }

        int erro = 0;
        if (opcao == 1) {
            erro = gpu_send_sprite(0, 32, 32, 1, 0, 1) ||
                   gpu_send_sprite(1, 84, 32, 1, 0, 1) ||
                   gpu_send_sprite(2, 136, 32, 1, 0, 1);
        } else if (opcao == 2) {
            unsigned id, x, y, vis, espelho, transparente;
            printf("ID (0..31), X (0..304), Y (0..224): "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) ||
                sscanf(linha, "%u %u %u", &id, &x, &y) != 3 ||
                id > 31 || x > 304 || y > 224) {
                puts("Parametros invalidos. Exemplo: 0 80 40"); continue;
            }
            printf("Visivel? (1 sim, 0 ocultar): "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u", &vis) != 1 || vis > 1) continue;
            puts("Espelho: 0 normal, 1 horizontal, 2 vertical, 3 ambos.");
            printf("Espelho (0..3): "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u", &espelho) != 1 || espelho > 3) continue;
            printf("Indice de cor 00 transparente? (1 sim, 0 nao): "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u", &transparente) != 1 || transparente > 1) continue;
            erro = gpu_send_sprite(id, x, y, vis, espelho, transparente);
        } else if (opcao == 4) {
            unsigned x, y, cor;
            mostrar_cores();
            printf("Tile X (0..39), Y (0..29), cor HEX: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u %x", &x, &y, &cor) != 3 ||
                x > 39 || y > 29 || cor > 0xFF) {
                puts("Parametros invalidos. Exemplo: 10 5 E0"); continue;
            }
            erro = gpu_send_tile(x, y, cor);
        } else if (opcao == 5) {
            unsigned direcao, tiles;
            puts("Direcao da camera: 0 direita, 1 esquerda, 2 cima, 3 baixo.");
            printf("Direcao e quantidade de tiles (1..15): "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u", &direcao, &tiles) != 2 ||
                direcao > 3 || tiles < 1 || tiles > 15) {
                puts("Parametros invalidos. Exemplo: 0 3"); continue;
            }
            erro = gpu_send_scroll(direcao, tiles);
        } else if (opcao == 6) {
            unsigned x1, y1, x2, y2, x3, y3, cor;
            mostrar_cores();
            printf("Ponto 1 - X1 Y1 COR em HEX: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u %x", &x1, &y1, &cor) != 3 ||
                x1 > 319 || y1 > 239 || cor > 0xFF) {
                puts("Ponto invalido. Exemplo: 40 40 E0"); continue;
            }
            printf("Ponto 2 - X2 Y2: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u", &x2, &y2) != 2 || x2 > 319 || y2 > 239) continue;
            printf("Ponto 3 - X3 Y3: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u", &x3, &y3) != 2 || x3 > 319 || y3 > 239) continue;
            erro = gpu_send_triangle(x1, y1, x2, y2, x3, y3, cor);
        } else if (opcao == 7) {
            unsigned x1, y1, x2, y2, cor;
            mostrar_cores();
            puts("P1 e P2 sao cantos opostos. Para quadrado, use lados iguais.");
            printf("Ponto 1 - X1 Y1 COR em HEX: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u %x", &x1, &y1, &cor) != 3 ||
                x1 > 319 || y1 > 239 || cor > 0xFF) {
                puts("Ponto invalido. Exemplo: 40 40 1C"); continue;
            }
            printf("Ponto 2 - X2 Y2: "); fflush(stdout);
            if (!ler_linha(linha, sizeof linha) || sscanf(linha, "%u %u", &x2, &y2) != 2 ||
                x2 > 319 || y2 > 239 || x1 == x2 || y1 == y2) continue;
            erro = gpu_send_rectangle(x1, y1, x2, y2, cor);
        } else if (opcao == 8) {
            erro = gpu_send_vsync();
        } else {
            continue;
        }

        if (terminar_comando(erro) != 0) break;
    }

    gpu_close();
    return 0;
}
