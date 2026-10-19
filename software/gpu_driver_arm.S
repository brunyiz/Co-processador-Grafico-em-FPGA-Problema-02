/* Codificacao da ISA grafica e acesso ordenado aos registradores MMIO.
 * ABI: parametros nos registradores r0-r3; argumentos seguintes na pilha.
 */
.syntax unified
.arch armv7-a
.arm
.text

.global gpu_pack_scroll
.type gpu_pack_scroll, %function
gpu_pack_scroll:
    and r0, r0, #3
    lsl r0, r0, #26
    and r1, r1, #15
    lsl r1, r1, #22
    orr r0, r0, r1
    mov r12, #6
    lsl r12, r12, #28
    orr r0, r0, r12
    bx lr
.size gpu_pack_scroll, .-gpu_pack_scroll

.global gpu_pack_tile
.type gpu_pack_tile, %function
gpu_pack_tile:
    and r0, r0, #63
    lsl r0, r0, #22
    and r1, r1, #31
    lsl r1, r1, #17
    orr r0, r0, r1
    and r2, r2, #255
    orr r0, r0, r2
    mov r12, #1
    lsl r12, r12, #28
    orr r0, r0, r12
    bx lr
.size gpu_pack_tile, .-gpu_pack_tile

.global gpu_pack_sprite
.type gpu_pack_sprite, %function
gpu_pack_sprite:
    push {r4, r5, lr}
    ldr r4, [sp, #12]       /* espelhamento, quinto argumento */
    ldr r5, [sp, #16]       /* transparencia, sexto argumento */
    and r0, r0, #31
    lsl r0, r0, #23
    and r1, r1, #511
    lsl r1, r1, #14
    orr r0, r0, r1
    and r2, r2, #255
    lsl r2, r2, #6
    orr r0, r0, r2
    and r3, r3, #1
    lsl r3, r3, #5
    orr r0, r0, r3
    and r1, r4, #2
    lsl r1, r1, #3         /* bit 1 do parametro -> bit 4 vertical */
    orr r0, r0, r1
    and r1, r4, #1
    lsl r1, r1, #3         /* bit 0 do parametro -> bit 3 horizontal */
    orr r0, r0, r1
    and r1, r5, #1
    lsl r1, r1, #2
    orr r0, r0, r1
    mov r12, #2
    lsl r12, r12, #28
    orr r0, r0, r12
    pop {r4, r5, pc}
.size gpu_pack_sprite, .-gpu_pack_sprite

.global gpu_pack_vsync
.type gpu_pack_vsync, %function
gpu_pack_vsync:
    mov r0, #5
    lsl r0, r0, #28
    bx lr
.size gpu_pack_vsync, .-gpu_pack_vsync

.global gpu_pack_triangle
.type gpu_pack_triangle, %function
gpu_pack_triangle:
    and r0, r0, #3
    lsl r0, r0, #26
    and r1, r1, #511
    lsl r1, r1, #17
    orr r0, r0, r1
    and r2, r2, #255
    lsl r2, r2, #9
    orr r0, r0, r2
    and r3, r3, #255
    lsl r3, r3, #1
    orr r0, r0, r3
    mov r12, #4
    lsl r12, r12, #28
    orr r0, r0, r12
    bx lr
.size gpu_pack_triangle, .-gpu_pack_triangle

.global gpu_pack_rectangle
.type gpu_pack_rectangle, %function
gpu_pack_rectangle:
    and r0, r0, #3
    lsl r0, r0, #26
    and r1, r1, #511
    lsl r1, r1, #17
    orr r0, r0, r1
    and r2, r2, #255
    lsl r2, r2, #9
    orr r0, r0, r2
    and r3, r3, #255
    lsl r3, r3, #1
    orr r0, r0, r3
    mov r12, #3
    lsl r12, r12, #28
    orr r0, r0, r12
    bx lr
.size gpu_pack_rectangle, .-gpu_pack_rectangle

.global gpu_mmio_write32
.type gpu_mmio_write32, %function
gpu_mmio_write32:
    dmb sy
    str r1, [r0]
    dmb sy
    ldr r2, [r0]           /* readback para concluir a escrita no barramento */
    dmb sy
    bx lr
.size gpu_mmio_write32, .-gpu_mmio_write32

.global gpu_mmio_read32
.type gpu_mmio_read32, %function
gpu_mmio_read32:
    dmb sy
    ldr r0, [r0]
    dmb sy
    bx lr
.size gpu_mmio_read32, .-gpu_mmio_read32

.section .note.GNU-stack,"",%progbits
