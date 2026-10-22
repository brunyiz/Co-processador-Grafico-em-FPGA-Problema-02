
# Co-processador-Grafico-em-FPGA-Problema-02

Núcleo de um coprocessador gráfico programável implementado em Verilog na plataforma Terasic DE1-SoC (Intel/Altera Cyclone V). O projeto dá continuidade ao núcleo gráfico desenvolvido no Problema 01, transformando-o em uma arquitetura programável organizada de forma semelhante a processadores convencionais, com ISA de 32 bits, unidade de busca de instruções, unidade de controle, datapath, banco de registradores, ULA e registrador de status, integrando os motores gráficos (background, sprites e polígonos) como unidades funcionais acionadas por instruções.

Projeto desenvolvido para a disciplina **MI - Sistemas Digitais** (Problema 02, semestre 2026.2).

Docente: *Angelo Duarte"

Discentes:
- *Bruna de Almeida Nascimento*
- *Carlos Daniel da Silva Jesus*
- *Diego Mercês Almeida*

---

## Sumário

- [Requisitos](#requisitos)
- [Arquitetura](#arquitetura)
- [ISA](#isa)
- [Hardware e Ferramentas](#hardware-e-ferramentas)
- [Estrutura do Repositório](#estrutura-do-repositório)
- [Módulos do Sistema](#módulos-do-sistema)
- [Programa de Demonstração](#programa-de-demonstração)
- [Compilação e Programação](#compilação-e-programação)
- [Testes](#testes)
- [Resultados e Análise](#resultados-e-análise)
- [Funcionalidades Não Atendidas](#funcionalidades-não-atendidas)
- [Autores](#autores)

---

## Requisitos

### Requisitos Funcionais

#### Arquitetura mínima

O sistema deve possuir, no mínimo:

- Instruction Set Architecture (ISA) de 32 bits.
- Unidade de busca de instruções.
- Registrador de Instrução (IR).
- Unidade de Controle.
- Banco de registradores.
- Unidade Lógica e Aritmética (ULA).
- Datapath.
- Registrador de status.
- Unidades funcionais gráficas (motores de background, sprites e polígonos).
- Compositor.
- Controlador VGA.

#### Unidades funcionais mínimas

1. Unidade de busca de instruções.
2. Unidade de Controle.
3. Unidade Lógica e Aritmética.
4. Motor de Background.
5. Motor de Sprites.
6. Rasterizador de Polígonos.
7. Unidade de Controle de Quadro.
8. Compositor.
9. Controlador VGA.

O compositor, a unidade de controle de quadro e o controlador VGA devem operar continuamente, independentemente da execução das instruções.

#### Programa gráfico

Deve existir, conforme a estratégia adotada pela equipe:

- **Busca ativa**: memória de instruções interna ao projeto contendo um pequeno programa gráfico armazenado em arquivo `.mif` ou `.hex`.
- **Busca passiva**: arquitetura projetada para receber instruções de uma fila de comandos proveniente da interface MMIO com o processador ARM, acompanhada de um programa em Assembly do ARM que use os recursos do coprocessador.

**Estratégia adotada pela equipe: busca passiva.**

#### Programa de demonstração

- Pelo menos um programa escrito em Assembly da ISA criada pela equipe.
- Sintaxe da ISA definida pela própria equipe.

#### Comunicação e sincronização

- Mecanismo de sincronização com o sinal VGA (ex.: sinais `valid`, `busy`, `done`).
- Toda operação do coprocessador deve ser consequência da execução de uma instrução pertencente à ISA definida.

#### Herança do Problema 01

- Motores de background, sprites e polígonos tratados como unidades funcionais do novo coprocessador.
- Integração com o compositor, a paleta e a saída VGA já existentes.

### Requisitos Não Funcionais

- Descrição integral em Verilog, com arquitetura modular (controle, datapath, memórias, unidades funcionais e saída de vídeo separados).
- Todos os registradores e memórias com estratégia definida de reinicialização ou inicialização.
- Ausência de instabilidade visual, perda de sincronismo ou pixels indefinidos após a inicialização.
- Uso de memórias em bloco M10K sintetizadas a partir de IPs do Quartus.
- Código-fonte com organização e comentários que permitam manutenção por terceiros.

### Entregáveis Obrigatórios

- Código RTL completo do coprocessador gráfico e do top-level utilizado na DE1-SoC.
- Projeto Quartus com todos os arquivos necessários para compilação e programação da placa.
- Repositório GitHub organizado, contendo código, documentação, arquivos de síntese e instruções de reprodução.

---

## Arquitetura

![Diagrama de alto nível](images/diagrama_alto_nivel.png)

No diagrama, `KEY0` e `CLOCK50MHZ` entram em `CLOCK_RESET`; o `CONTROLADOR_VGA` fornece as coordenadas aos motores; a `UNIDADE DE CONTROLE` aciona os motores (setas verdes) e escreve no `STATUS`, que o ARM lê de volta; a `FIFO` também alimenta o `STATUS` (setas vermelhas).

O diagrama mostra a visão de alto nível: o banco de registradores, o datapath e a ULA ficam **dentro** do bloco `UNIDADE DE CONTROLE` (módulos `datapath_grafico`, `banco_registradores_graficos` e `ula_grafica`) e por isso não aparecem como blocos separados. O bloco `FIFO` + `IR` corresponde à unidade de busca (`fila_comandos.v`). Não há módulo separado de controle de quadro (ver [Sincronização com VGA](#sincronização-com-vga)).

O sistema tem dois planos independentes:

- **Plano de execução de instruções (busca passiva):** o programa do ARM (HPS) escreve palavras de 32 bits em PIOs mapeados na ponte *lightweight* HPS→FPGA. As palavras passam por um handshake `REQ/ACK`, entram em uma FIFO e no registrador de instrução (IR), e a unidade de controle as decodifica e aciona os motores gráficos.
- **Plano de vídeo contínuo:** controlador VGA, motores (leitura), compositor e paleta operam o tempo todo, sem depender de instruções, lendo o estado que as instruções deixaram nos motores.

### Unidades Funcionais

| Unidade | Arquivo | Função |
|---|---|---|
| Unidade de busca + IR | `fila_comandos.v` | Recebe a palavra do ARM (REQ/ACK), guarda em FIFO de 8 palavras e mantém o IR até a conclusão (`done`). |
| Unidade de Controle | `unidade_controle.v` | FSM (`IDLE, SETTLE, RUN, TOG, TOGWAIT, WAIT_VBLANK`) que decodifica o opcode, valida a instrução e gera os pulsos para os motores. |
| Datapath | `datapath_grafico.v` | Banco de registradores + duas ULAs que comparam a posição atual do sprite com o alvo da instrução. |
| Banco de registradores | `banco_registradores_graficos.v` | `r0..r7` de 32 bits: vértices/cor do triângulo (`r0..r2`) e pontos/cor do retângulo (`r3..r4`). |
| ULA | `ula_grafica.v` | Soma, subtração, AND, OR e flags `zero`/`menor`. Em uso: duas instâncias subtraem/comparam a posição atual do sprite com o alvo da instrução `SPRITE` (malha fechada); soma, AND e OR estão disponíveis, mas não são usadas por nenhuma instrução gráfica. |
| Registrador de status | `main.v` (`status_reg`) | `GPU_STATUS`: assinatura `0x4750` em `[31:16]` e `DONE, BUSY, READY, ERRO, ACK` em `[4:0]`. |
| Motor de Background | `motor_background.v`, `mapa_ram.v` | Tilemap 40×30 em RAM de duas portas (tiles de cor sólida, 8×8 px) e *scroll* relativo com *wrap*. |
| Motor de Sprites | `motor_sprites.v`, `sprite_rom.v` | 32 sprites 16×16 (registradores de atributos + ROM de padrões). |
| Rasterizador de Polígonos | `rasterizador_poligonos.v` | Triângulo (funções de borda) e retângulo/quadrado preenchidos. |
| Compositor | `compositor.v` | Combina as três camadas: sprite > polígono > background; índice `00` transparente. |
| Paleta | `ram_paleta.v` | Decodificador fixo RGB332 → RGB888. |
| Controlador VGA | `controlador_vga.v` | 640×480@60 Hz, pixel lógico 320×240 com ampliação 2×2; gera o pulso `inicio_vblank`. |
| Clock/Reset | `clock_reset.v` | Divide 50 MHz para 25 MHz e sincroniza o reset. |
| Top-level | `DE1_SOC_golden_top.v`, `main.v` | Integra HPS (`soc_system`) e o coprocessador. |

### Fluxo de Dados e Controle

1. O programa no ARM monta a palavra (`gpu_pack_*`) e a escreve no PIO `CMD`; em seguida alterna o PIO `REQ`.
2. A FPGA sincroniza `REQ` (50 → 25 MHz, 2 flip-flops), empilha a palavra na FIFO e responde com `ACK` (toggle).
3. A FIFO apresenta a palavra ao IR com `instr_valid`. A unidade de controle executa e ativa `done`; só então a FIFO entrega a próxima.
4. Instruções de várias palavras (retângulo: 2; triângulo: 3) são acumuladas no banco de registradores e o desenho só dispara na última, em ordem obrigatória. Fora de ordem → `ERRO` e descarte do polígono parcial.
5. Registradores de `TILE` e `SCROLL` atualizam o background; `SPRITE` atualiza posição/atributos; `VSYNC` mantém `BUSY` até o início do VBlank.
6. O compositor escolhe o pixel de cada camada e a paleta converte o índice RGB332 em cor para a VGA.

Endereços na ponte *lightweight* (base `0xFF200000`):

| Offset | PIO | Sentido |
|---|---|---|
| `0x00` | `CMD` | ARM → FPGA (palavra de instrução) |
| `0x10` | `REQ` | ARM → FPGA (toggle de requisição) |
| `0x20` | `STATUS` | FPGA → ARM |

### Sincronização com VGA

- `READY`: há espaço na FIFO para nova palavra. `BUSY`: UC ou FIFO ocupadas. `DONE`: FIFO vazia e UC ociosa. `ACK`: palavra aceita. `ERRO`: instrução inválida.
- O controlador VGA gera o pulso `inicio_vblank` (início da linha 480). A instrução `VSYNC` bloqueia a fila até o **próximo** VBlank, permitindo agrupar alterações visuais e evitar *tearing*.
- Não existe módulo dedicado de controle de quadro nem contador de quadros: a sincronização com o quadro é feita pelo pulso `inicio_vblank` do controlador VGA, consumido pela instrução `VSYNC` na unidade de controle. O compositor e o controlador VGA operam continuamente, independentes das instruções.
- As instruções **não** são aplicadas de forma atômica no mesmo quadro: cada uma é executada na ordem em que sai da FIFO. Um programa que começa com `VSYNC` faz as instruções seguintes de 1 ciclo (`TILE`, `SCROLL`, retângulo, triângulo) executarem em sequência logo após o início do VBlank, mas `SPRITE` leva milissegundos (ver Desempenho).

---

## ISA

Palavra de 32 bits, opcode de 4 bits em `[31:28]`. Especificação completa em [`docs/ISA_instruction.txt`](docs/ISA_instruction.txt).

### Formatos de Instrução

| Instrução | Campos |
|---|---|
| `TILE` | `[27:22]` X · `[21:17]` Y · `[7:0]` cor RGB332 |
| `SPRITE` | `[27:23]` ID · `[22:14]` X · `[13:6]` Y · `[5]` visível · `[4]` espelho V · `[3]` espelho H · `[2]` transparente |
| `RETANGULO` (2 palavras) | `[27:26]` etapa · `[25:17]` X · `[16:9]` Y · `[8:1]` cor (etapa 00) |
| `TRIANGULO` (3 palavras) | `[27:26]` etapa (00/01/10) · `[25:17]` X · `[16:9]` Y · `[8:1]` cor (etapa 00) |
| `VSYNC` | `[27:0]` = 0 |
| `SCROLL` | `[27:26]` direção (00 dir, 01 esq, 10 cima, 11 baixo) · `[25:22]` tiles (1–15) |

### Conjunto de Instruções

| Opcode | Instrução | Palavras | Efeito |
|---|---|---|---|
| `0001` | `TILE` | 1 | Escreve cor sólida em um tile (X 0–39, Y 0–29). |
| `0010` | `SPRITE` | 1 | Move/configura um dos 32 sprites; a UC move em malha fechada até o alvo. |
| `0011` | `RETANGULO` | 2 | Retângulo/quadrado preenchido por dois pontos opostos + cor. |
| `0100` | `TRIANGULO` | 3 | Triângulo preenchido por P1 (+cor), P2, P3 em ordem. |
| `0101` | `VSYNC` | 1 | Espera o início do próximo VBlank. |
| `0110` | `SCROLL` | 1 | Desloca a câmera do background (relativo, com *wrap*). |

Qualquer outro opcode, tile fora da grade, `SCROLL` com quantidade 0 ou etapa fora de ordem ativa `ERRO`.

### Convenções de Registradores

| Registrador | Uso |
|---|---|
| `r0` | Triângulo: P1 (X `[24:16]`, Y `[15:8]`) e cor `[7:0]` |
| `r1`, `r2` | Triângulo: P2 e P3 (X `[16:8]`, Y `[7:0]`) |
| `r3` | Retângulo: P1 e cor |
| `r4` | Retângulo: P2 |
| `r5..r7` | Reservados (sem uso na versão atual) |

Os registradores não são endereçáveis pelo programador: são escritos pela UC conforme a etapa da instrução.

---

## Hardware e Ferramentas

| Item | Especificação |
|---|---|
| Placa | Terasic DE1-SoC |
| FPGA | Intel/Altera Cyclone V `5CSEMA5F31C6` (com HPS ARM Cortex-A9) |
| Ferramenta de síntese | Intel Quartus Prime 20.1.1 *Lite* + Platform Designer (os IPs do `soc_system.qsys` foram salvos na versão 25.1) |
| Linguagem de descrição | Verilog |
| Saída de vídeo | VGA 640×480 @ 60 Hz (320×240 lógico, ampliação 2×2), cor RGB332 |
| Clock de entrada | 50 MHz (`CLOCK_50`) |
| Clock de pixel | 25 MHz (divisor de clock em `clock_reset.v`, declarado em `clocks.sdc`) |

---

## Estrutura do Repositório

```
.
├── docs/
│   ├── README.md                      este documento
│   ├── ISA_instruction.txt            especificação da ISA
│   ├── diagrama_alto_nivel.png        diagrama de blocos
│   └── images/                        diagrama e fotos da demonstração
├── software/                          programa do HPS (ARM)
│   ├── gpu_driver.c                   driver MMIO (init, envio, espera)
│   ├── gpu_driver_arm.S               rotinas em Assembly ARM (MMIO e empacotamento)
│   ├── menu.c                         menu de demonstração
│   └── montador_gasm.py               montador da sintaxe da ISA (.gasm)
└── src/                               projeto Quartus
    ├── PBL02_G04_coprocessador_grafico.qpf / .qsf
    ├── soc_system.qsys                sistema HPS (Platform Designer)
    ├── DE1_SOC_golden_top.v           top-level da placa
    ├── main.v                         integração do coprocessador
    ├── clock_reset.v · clocks.sdc
    ├── fila_comandos.v                busca passiva + FIFO + IR
    ├── unidade_controle.v
    ├── datapath_grafico.v · banco_registradores_graficos.v · ula_grafica.v
    ├── motor_background.v · mapa_ram.v/.qip · background_map.mif
    ├── motor_sprites.v · sprite_rom.v/.qip · sprite_patterns.mif
    ├── rasterizador_poligonos.v
    ├── compositor.v · ram_paleta.v · controlador_vga.v
    └── decodificador_hex.v            displays de depuração
```

Arquivos gerados (`src/soc_system/`, `db/`, `output_files/`, `.sof`...) não são versionados; veja [Compilação e Programação](#compilação-e-programação).

---

## Módulos do Sistema

### `fila_comandos` (unidade de busca + IR)
- **Entradas:** `GPU_CMD` (palavra), `GPU_REQ` (toggle), `done` da UC.
- **Processamento:** sincroniza `REQ`, empilha em FIFO de 8 palavras, mantém o IR até `done`.
- **Saídas:** `instr`, `instr_valid`, `ACK`, `READY`, `BUSY`, `DONE`.

### `unidade_controle`
- **Entradas:** `instr`, `instr_valid`, `inicio_vblank`, posição atual do sprite.
- **Processamento:** FSM de 6 estados; só `SPRITE` (posicionamento em malha fechada) e `VSYNC` usam mais de um estado; os demais opcodes concluem em um ciclo. Valida campos e ordem das etapas.
- **Saídas:** `busy`, `done`, `instr_invalida`, escrita de tile, pulso de scroll, pulsos de desenho, atributos/movimento de sprite.

### `datapath_grafico`, `banco_registradores_graficos`, `ula_grafica`
- Guardam os operandos de polígonos (`r0..r4`) e comparam posição atual × alvo do sprite (subtração; flags `menor`/`zero`).

### `motor_background` / `mapa_ram`
- **Entradas:** posição lógica (X, Y) da VGA, escrita de tile, pulso de scroll.
- **Processamento:** endereça o tilemap 40×30 com deslocamento de scroll (*wrap*).
- **Saída:** índice de cor do pixel.

### `motor_sprites` / `sprite_rom`
- **Entradas:** posição lógica, atributos e movimento vindos da UC.
- **Processamento:** 32 sprites 16×16; padrão do sprite *n* = padrão *n* da ROM; espelhamento H/V; índice `00` transparente quando o bit de transparência está ativo.
- **Saídas:** índice de cor e `pixel_valido`.

### `rasterizador_poligonos`
- **Entradas:** pulsos `tri_desenhar` / `ret_desenhar`, vértices e cor.
- **Processamento:** funções de borda por pixel (triângulo) e comparação de limites (retângulo). Mantém **um** polígono por vez.
- **Saída:** índice de cor (`0` = transparente).

### `compositor`, `ram_paleta`, `controlador_vga`
- Prioridade sprite > polígono > background; paleta fixa RGB332 → RGB888; temporização VGA 640×480@60 Hz com `inicio_vblank`.

---

## Programa de Demonstração

**Programa do ARM (busca passiva):** `software/menu.c` + `software/gpu_driver.c` + `software/gpu_driver_arm.S`. O menu envia, por SSH no terminal do HPS, instruções de sprite (posição, visibilidade, espelho, transparência), tile, scroll, retângulo, triângulo e `VSYNC`.

> **Não conforme:** o driver ficou **dividido entre C e Assembly**, o que não podia. Em Assembly ARM estão apenas `gpu_pack_*` (montagem das palavras da ISA) e `gpu_mmio_write32/read32` (acesso aos PIOs com barreiras `DMB`), em `gpu_driver_arm.S`. Em **C** (`gpu_driver.c`) estão a inicialização (`gpu_init`, `/dev/mem` e `mmap`), a espera por `READY`/`ACK`/`DONE` e o envio das instruções (`gpu_send_*`); o menu (`menu.c`) também é em C. O requisito exige um programa em Assembly ARM que use o coprocessador, então este ponto **não foi atendido** (ver [Funcionalidades Não Atendidas](#funcionalidades-não-atendidas)).

**Assembly da ISA da equipe:** `software/montador_gasm.py` converte arquivos `.gasm` (mnemônicos `TILE`, `SPRITE`, `RECT_P1/P2`, `TRI_P1/P2/P3`, `BG_SCROLL`, `VSYNC`) nas palavras de 32 bits. Exemplo de programa nessa sintaxe (cores em RGB332 hexadecimal; `SPRITE id x y visível espelho transparente`):

```
VSYNC                          # espera o início do próximo VBlank
TILE 8 28 0x03                 # tile azul
RECT_P1 40 120 0x1F            # retângulo ciano: ponto 1 + cor
RECT_P2 100 220                # ponto 2 (dispara o desenho)
TRI_P1 200 60 0xE0             # triângulo vermelho: P1 + cor
TRI_P2 260 60
TRI_P3 230 20                  # P3 (dispara o desenho)
BG_SCROLL RIGHT 2              # câmera 2 tiles à direita
SPRITE 3 188 32 1 3 1          # sprite 3, espelho X+Y, transparente
```

Montagem: `python3 software/montador_gasm.py programa.gasm` imprime uma palavra hexadecimal por instrução (`--c` gera um vetor C). Esse listado é um exemplo da sintaxe; o programa não está versionado como arquivo nem integrado ao driver: o envio das palavras é feito pelo menu.

---

## Compilação e Programação

1. Abra `src/PBL02_G04_coprocessador_grafico.qpf` no Quartus Prime.
2. Abra `src/soc_system.qsys` no Platform Designer e clique em **Generate HDL** (Verilog) para recriar `src/soc_system/`.
3. Se solicitado, execute os scripts de pinos/SDRAM do HPS gerados em `src/soc_system/synthesis/submodules/`.
4. Execute **Full Compilation** (o `clocks.sdc` já está no `.qsf`).
5. Conecte o monitor VGA e a USB-Blaster, programe o `.sof` pelo Programmer.
6. No Linux da placa, habilite a ponte HPS→FPGA, copie `software/` e compile:

```bash
cd software
gcc menu.c gpu_driver.c gpu_driver_arm.S -o gpu_menu -lrt
sudo ./gpu_menu
```

Reset: botão `KEY0` da placa (ativo em nível baixo), sincronizado em `clock_reset.v`.

---

## Testes

### Cenários de Teste

| Cenário | Descrição | Método | Evidência |
|---|---|---|---|
| Transparência | Sprite com bit de transparência: índice `00` deixa ver as camadas inferiores | Menu do HPS na placa | Figura 2: o fundo aparece ao redor dos sprites |
| Sobreposição | Sprites e polígono sobrepostos ao background | Menu do HPS na placa | Figuras 1 e 2: sprites e retângulo cobrem o background |
| Scroll com *wrap* | Linhas do mapa reaparecem no lado oposto | Menu do HPS na placa | Figura 3 |
| Troca de buffers | Não há *frame buffer*; `VSYNC` sincroniza alterações com o VBlank | Ver [Funcionalidades Não Atendidas](#funcionalidades-não-atendidas) | Não se aplica |

### Scripts de Automação

`software/montador_gasm.py` (montagem de `.gasm`) e comandos de geração do HPS, compilação e programação:

```bash
cd src && qsys-generate soc_system.qsys --synthesis=VERILOG
quartus_sh --flow compile PBL02_G04_coprocessador_grafico
quartus_pgm -m jtag -o "p;output_files/PBL02_G04_coprocessador_grafico.sof@2"   # dispositivo 2 da cadeia JTAG da DE1-SoC
```

---

## Resultados e Análise

### Desempenho

- Instruções `TILE`, `SCROLL`, `RETANGULO`, `TRIANGULO`: concluem em 1 ciclo de 25 MHz na UC após chegarem ao IR.
- `SPRITE`: movimento em malha fechada de ≈ 1 px a cada 14 ms; um deslocamento longo (≈ 300 px) leva da ordem de 4 s e bloqueia a fila até concluir.

### Demonstração em Hardware

Resultados observados na DE1-SoC, com monitor VGA, programa enviado pelo HPS:

| Figura | O que mostra |
|---|---|
| ![Background](images/cenario_background.jpg)<br>*Figura 1 — Background (tilemap 40×30)* | Mapa de tiles de cor sólida em estado inicial, sem sprites e sem polígonos. |
| ![Sprites e retângulo](images/cenario_sprites_retangulo.jpg)<br>*Figura 2 — Sprites e retângulo* | Cinco sprites 16×16 com fundo transparente sobre o background, e um retângulo ciano (polígono) cobrindo parte do mapa. |
| ![Scroll e sprites](images/cenario_scroll_sprites.jpg)<br>*Figura 3 — Scroll com wrap* | Mapa deslocado verticalmente: as linhas de baixo reaparecem no topo (*wrap*), com sprites posicionados sobre o fundo. |

---

## Funcionalidades Não Atendidas

- **Troca de buffers:** não há *frame buffer*; a sincronização é feita por `VSYNC`.
- **Unidade de controle de quadro** dedicada e contador de quadros: ausentes (há apenas o pulso `inicio_vblank` do controlador VGA).
- **Padrões de tile e paleta programável:** o tile é cor sólida (índices RGB332 da VGA) e a paleta é fixa, conforme liberado pelo tutor; sprites sem seleção de paleta (idem).
- **Polígonos:** o rasterizador guarda um único polígono por vez.
- **Sprite:** movimento lento (≈ 14 ms/pixel); padrão fixo por índice; posição limitada a 0..304 × 0..224.
- **Driver dividido entre C e Assembly:** apenas o empacotamento das palavras e o acesso MMIO (`gpu_driver_arm.S`) estão em Assembly ARM; inicialização, espera e envio das instruções estão em C (`gpu_driver.c`) e o menu é em C. O requisito pede o driver/programa do ARM em Assembly, portanto não foi cumprido.
- **Execução simultânea das instruções:** não há lógica de sincronização que aplique várias instruções no mesmo quadro; elas executam em sequência (ver [Sincronização com VGA](#sincronização-com-vga)).
- **Testbenches, relatório de utilização/timing e testes de espelhamento, comandos inválidos e `BUSY`/`DONE`:** não documentados nesta entrega; a validação foi feita na placa (ver Demonstração em Hardware).

### Melhorias Possíveis

- **Corrigir o driver:** portar `gpu_driver.c` (inicialização por `open`/`mmap`, handshake REQ/ACK e envio das instruções) integralmente para Assembly ARM.
- **Atualização atômica por quadro:** registradores sombra nos motores, copiados todos juntos no `inicio_vblank`, para que qualquer instrução (inclusive `SPRITE`) apareça no mesmo quadro; exige alterar o RTL.
- Escrever atributos do sprite diretamente (posição em poucos ciclos) e instrução para trocar o padrão.
- Lista de polígonos ou *frame buffer* com troca no VBlank.
- Contador de quadros no `STATUS`; sincronizador para `GPU_STATUS` ao cruzar de 25 MHz para o PIO.
- Paleta em RAM programável (M10K) e padrões de tile.

---

## Autores

- *Bruna de Almeida Nascimento*
- *Carlos Daniel da Silva Jesus*
- *Diego Mercês Almeida*

Bacharelado em Engenharia de Computação - UEFS
Disciplina: MI - Sistemas Digitais (2026.2)

---

## Referências

- TERASIC. **DE1-SoC User Manual**, rev. F. Terasic Technologies Inc., 2018.
- UNIVERSIDADE ESTADUAL DE FEIRA DE SANTANA. **Problema #2 — 2026.2: Sistema Digital**. Departamento de Tecnologia, Área de Eletrônica, 2026.
- PINEDA, J. **A Parallel Algorithm for Polygon Rasterization**. SIGGRAPH '88, 1988.
