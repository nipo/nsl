library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_wishbone, nsl_jtag, nsl_data, work;
use neorv32.neorv32_package.all;
use work.processor.all;
use nsl_wishbone.wishbone.all;

entity neorv32_processor is
  generic(
    clock_i_hz_c : natural;
    wb_config_c : nsl_wishbone.wishbone.wb_config_t;

    tap_enable_c : boolean := false;
    vendor_id_c : std_ulogic_vector := x"00000000";

    config_c : neorv32_config_t := neorv32_config_minimal_c;
    hart_id_c  : std_ulogic_vector := x"00000000";
    uart_enable_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tap_i : in nsl_jtag.jtag.jtag_tap_i;
    tap_o : out nsl_jtag.jtag.jtag_tap_o;

    wb_o : out nsl_wishbone.wishbone.wb_req_t;
    wb_i : in nsl_wishbone.wishbone.wb_ack_t;

    uart_tx_o : out std_ulogic;
    uart_rx_i : in std_ulogic := '1';
    uart_rts_o : out std_ulogic;
    uart_cts_i : in std_ulogic := '0';
    
    irq_n_i : in std_ulogic := '1';

    gpio_o : out std_ulogic_vector(63 downto 0);
    gpio_i : in std_ulogic_vector(63 downto 0) := (others => '0')
    );
end neorv32_processor;

architecture beh of neorv32_processor is

  signal wb_tag_o : std_ulogic_vector(2 downto 0);
  signal wb_adr_o : std_ulogic_vector(31 downto 0);
  signal wb_dat_i : std_ulogic_vector(31 downto 0);
  signal wb_dat_o : std_ulogic_vector(31 downto 0);
  signal wb_we_o  : std_ulogic;
  signal wb_sel_o : std_ulogic_vector(3 downto 0);
  signal wb_stb_o : std_ulogic;
  signal wb_cyc_o : std_ulogic;
  signal wb_ack_i : std_ulogic;
  signal wb_err_i : std_ulogic;
  signal irq_s : std_ulogic;
  
begin

  -- Assertions like this would be better suited in the entity
  -- statement part (IEEE-1076-1993 Chap 1.1.3), but statements there
  -- are ignored by Vivado synthesis (maybe others). * sigh *

  assert wb_config_c.version = WB_B4
    report "This module only supports WB B4 version"
    severity failure;

  assert wb_config_c.bus_type = WB_CLASSIC_PIPELINED or wb_config_c.bus_type = WB_CLASSIC_STANDARD
    report "This module only supports classic bus type"
    severity failure;

  assert wb_config_c.adr_width = 32
    report "This module only supports 32-bit address"
    severity failure;

  assert wb_config_c.port_size_l2 = 5
    report "This module only supports 32-bit data"
    severity failure;

  assert wb_config_c.port_granularity_l2 = 3
    report "This module only supports byte granularity"
    severity failure;

  assert wb_config_c.tga_width = 3
    report "This module requires 3-bit address tag"
    severity failure;

  core: neorv32.neorv32_package.neorv32_top
    generic map (
      clock_frequency => clock_i_hz_c,
      hart_id         => hart_id_c,
      vendor_id       => vendor_id_c,

      on_chip_debugger_en => tap_enable_c,
      int_bootloader_en => true,

      cpu_extension_riscv_c      => config_c.riscv_c,
      cpu_extension_riscv_m      => config_c.riscv_m,
      cpu_extension_riscv_u      => config_c.riscv_u,
      cpu_extension_riscv_zicntr => config_c.riscv_zicntr,
      cpu_extension_riscv_zihpm  => config_c.riscv_zihpm,

      fast_mul_en   => config_c.fast_ops,
      fast_shift_en => config_c.fast_ops,

      pmp_num_regions     => config_c.pmp_nr,
      pmp_min_granularity => 4,

      hpm_num_cnts  => config_c.hpm_nr,
      hpm_cnt_width => 64,

      icache_en            => config_c.icache_en,
      icache_num_blocks    => config_c.icache_nb,
      icache_block_size    => config_c.icache_bs,
      icache_associativity => config_c.icache_as,

      dcache_en         => config_c.dcache_en,
      dcache_num_blocks => config_c.dcache_nb,
      dcache_block_size => config_c.dcache_bs,

      mem_ext_en         => true,
      mem_ext_timeout    => wb_config_c.timeout,
      mem_ext_pipe_mode  => wb_config_c.bus_type = WB_CLASSIC_PIPELINED,
      mem_ext_big_endian => wb_config_c.endian = WB_ENDIAN_BIG,
      mem_ext_async_rx   => true,
      mem_ext_async_tx   => true,

      io_mtime_en => config_c.mtime,
      io_uart0_en => uart_enable_c,
      io_gpio_num => 64
      )
    port map (
      clk_i  => clock_i,
      rstn_i => reset_n_i,

      jtag_trst_i => tap_i.trst,
      jtag_tck_i  => tap_i.tck,
      jtag_tdi_i  => tap_i.tdi,
      jtag_tms_i  => tap_i.tms,
      jtag_tdo_o  => tap_o.tdo.v,

      wb_tag_o => wb_tag_o,
      wb_adr_o => wb_adr_o,
      wb_dat_o => wb_dat_o,
      wb_we_o  => wb_we_o,
      wb_sel_o => wb_sel_o,
      wb_stb_o => wb_stb_o,
      wb_cyc_o => wb_cyc_o,

      wb_dat_i => wb_dat_i,
      wb_ack_i => wb_ack_i,
      wb_err_i => wb_err_i,

      mext_irq_i => irq_s,

      uart0_txd_o  => uart_tx_o,
      uart0_rxd_i  => uart_rx_i,
      uart0_rts_o  => uart_rts_o,
      uart0_cts_i  => uart_cts_i,

      gpio_o => gpio_o,
      gpio_i => gpio_i
      );

  irq_s <= not irq_n_i;
  
  wb_req: process(wb_tag_o, wb_adr_o, wb_dat_o, wb_we_o,
                  wb_sel_o, wb_stb_o, wb_cyc_o) is
  begin
    wb_o <= wbc_req_idle(wb_config_c);

    if wb_cyc_o = '1' then
      wb_o <= wbc_cycle(wb_config_c);

      if wb_stb_o = '1' then
        if wb_we_o = '1' then
          wb_o <= wbc_write(wb_config_c,
                            address => unsigned(wb_adr_o),
                            sel => wb_sel_o,
                            data => wb_dat_o,
                            address_tag => wb_tag_o);
        else
          wb_o <= wbc_read(wb_config_c,
                           address => unsigned(wb_adr_o),
                           address_tag => wb_tag_o);
        end if;
      end if;
    end if;
  end process;

  wb_ack: process(wb_i) is
  begin
    wb_dat_i <= (others => '-');
    wb_ack_i <= '0';
    wb_err_i <= '0';

    case wbc_term(wb_config_c, wb_i) is
      when WB_TERM_ACK =>
        wb_dat_i <= wbc_data(wb_config_c, wb_i);
        wb_ack_i <= '1';
      when WB_TERM_ERROR =>
        wb_err_i <= '1';
      when others =>
        null;
    end case;
  end process;
  
  tap_wrapper: if tap_enable_c
  generate
    signal dr_shift_s, ir_shift_s : std_ulogic;
  begin  
    tap_controller: nsl_jtag.tap.tap_controller
      port map(
        tck_i => tap_i.tck,
        tms_i => tap_i.tms,
        trst_i => tap_i.trst,
        ir_shift_o => ir_shift_s,
        dr_shift_o => dr_shift_s
        );
    tap_o.tdo.en <= ir_shift_s or dr_shift_s;
    tap_o.rtck <= tap_i.tck;
  end generate;

  tap_none: if not tap_enable_c
  generate
  begin  
    tap_o.tdo.en <= '0';
  end generate;

end architecture;
