# Clock da placa e clock de video produzido pelo divisor do projeto.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
create_generated_clock -name clock_vga -source [get_ports {CLOCK_50}] -divide_by 2 [get_registers {main_inst|divisor_clock|vga_clk}]
derive_pll_clocks
derive_clock_uncertainty
