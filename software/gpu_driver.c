#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define LW_BASE 0xFF200000UL
#define LW_SPAN 0x1000UL
#define REG_COMMAND 0x00U
#define REG_REQUEST 0x10U
#define REG_STATUS  0x20U
#define ACK   (1U << 0)
#define ERRO  (1U << 1)
#define READY (1U << 2)
#define BUSY  (1U << 3)
#define DONE  (1U << 4)
#define GPU_ID 0x4750U

static int mem_fd = -1;
static volatile uint32_t *mmio;
void gpu_close(void);

extern uint32_t gpu_pack_scroll(unsigned direcao, unsigned tiles);
extern uint32_t gpu_pack_tile(unsigned x, unsigned y, unsigned cor);
extern uint32_t gpu_pack_sprite(unsigned id, unsigned x, unsigned y,
                                unsigned visivel, unsigned espelho,
                                unsigned transparente);
extern uint32_t gpu_pack_vsync(void);
extern uint32_t gpu_pack_triangle(unsigned etapa, unsigned x, unsigned y,
                                  unsigned cor);
extern uint32_t gpu_pack_rectangle(unsigned etapa, unsigned x, unsigned y,
                                   unsigned cor);
extern void gpu_mmio_write32(volatile uint32_t *endereco, uint32_t valor);
extern uint32_t gpu_mmio_read32(volatile uint32_t *endereco);

static uint32_t ler_status(void) {
    return gpu_mmio_read32(&mmio[REG_STATUS / 4U]);
}

uint32_t gpu_status(void) {
    if (!mmio) return 0;
    return ler_status();
}

/* Espera um conjunto de bits com timeout; valida a assinatura do hardware. */
static int esperar(uint32_t mascara, uint32_t valor, unsigned segundos) {
    struct timespec inicio, agora, pausa = {0, 1000000L};
    if (clock_gettime(CLOCK_MONOTONIC, &inicio) != 0) return -1;
    for (;;) {
        uint32_t s = ler_status();
        if ((s >> 16) != GPU_ID) { errno = ENODEV; return -1; }
        if ((s & mascara) == valor) return 0;
        if (clock_gettime(CLOCK_MONOTONIC, &agora) != 0) return -1;
        int64_t decorrido = (int64_t)(agora.tv_sec - inicio.tv_sec) * 1000000000LL +
                            agora.tv_nsec - inicio.tv_nsec;
        if (decorrido >= (int64_t)segundos * 1000000000LL) {
            errno = ETIMEDOUT;
            return -1;
        }
        (void)nanosleep(&pausa, 0);
    }
}

int gpu_init(void) {
    void *mapeado;
    if (mmio) return 0;
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) return -1;
    mapeado = mmap(0, LW_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED,
                   mem_fd, (off_t)LW_BASE);
    if (mapeado == MAP_FAILED) {
        int salvo = errno;
        close(mem_fd); mem_fd = -1; errno = salvo;
        return -1;
    }
    mmio = (volatile uint32_t *)mapeado;
    if (esperar(ACK, gpu_mmio_read32(&mmio[REG_REQUEST / 4U]) & ACK, 5) != 0) {
        int salvo = errno;
        gpu_close(); errno = salvo;
        return -1;
    }
    return 0;
}

void gpu_close(void) {
    if (mmio) { munmap((void *)mmio, LW_SPAN); mmio = 0; }
    if (mem_fd >= 0) { close(mem_fd); mem_fd = -1; }
}

/* Uma palavra: READY libera espaco; ACK confirma a retirada pela FPGA. */
static int enviar_palavra(uint32_t palavra) {
    uint32_t req;
    if (!mmio) { errno = ENODEV; return -1; }
    req = gpu_mmio_read32(&mmio[REG_REQUEST / 4U]) & ACK;
    if (esperar(ACK, req, 30) != 0 || esperar(READY, READY, 30) != 0) return -1;
    gpu_mmio_write32(&mmio[REG_COMMAND / 4U], palavra);
    gpu_mmio_write32(&mmio[REG_REQUEST / 4U], req ^ ACK);
    return esperar(ACK, req ^ ACK, 30);
}

int gpu_wait_done(void) {
    if (esperar(BUSY | DONE, DONE, 120) != 0) return -1;
    if (ler_status() & ERRO) { errno = EPROTO; return -1; }
    return 0;
}

int gpu_send_scroll(unsigned direcao, unsigned tiles) {
    if (direcao > 3 || tiles < 1 || tiles > 15) { errno = EINVAL; return -1; }
    return enviar_palavra(gpu_pack_scroll(direcao, tiles));
}

int gpu_send_tile(unsigned x, unsigned y, unsigned cor) {
    if (x > 39 || y > 29 || cor > 255) { errno = EINVAL; return -1; }
    return enviar_palavra(gpu_pack_tile(x, y, cor));
}

int gpu_send_sprite(unsigned id, unsigned x, unsigned y, unsigned visivel,
                    unsigned espelho, unsigned transparente) {
    if (id > 31 || x > 304 || y > 224 || visivel > 1 || espelho > 3 || transparente > 1) {
        errno = EINVAL; return -1;
    }
    return enviar_palavra(gpu_pack_sprite(id, x, y, visivel, espelho, transparente));
}

int gpu_send_vsync(void) {
    return enviar_palavra(gpu_pack_vsync());
}

int gpu_send_triangle(unsigned x1, unsigned y1, unsigned x2, unsigned y2,
                      unsigned x3, unsigned y3, unsigned cor) {
    if (x1 > 319 || x2 > 319 || x3 > 319 || y1 > 239 || y2 > 239 || y3 > 239 || cor > 255) {
        errno = EINVAL; return -1;
    }
    if (enviar_palavra(gpu_pack_triangle(0, x1, y1, cor)) != 0 ||
        enviar_palavra(gpu_pack_triangle(1, x2, y2, 0)) != 0 ||
        enviar_palavra(gpu_pack_triangle(2, x3, y3, 0)) != 0) return -1;
    return 0;
}

int gpu_send_rectangle(unsigned x1, unsigned y1, unsigned x2, unsigned y2,
                       unsigned cor) {
    if (x1 > 319 || x2 > 319 || y1 > 239 || y2 > 239 || x1 == x2 || y1 == y2 || cor > 255) {
        errno = EINVAL; return -1;
    }
    if (enviar_palavra(gpu_pack_rectangle(0, x1, y1, cor)) != 0 ||
        enviar_palavra(gpu_pack_rectangle(1, x2, y2, 0)) != 0) return -1;
    return 0;
}
