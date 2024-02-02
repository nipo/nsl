library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_wishbone, nsl_jtag;
use nsl_wishbone.wishbone.all;

package processor is

  -- Core configuration. Some default configs are defined below. User
  -- may create its own.
  type neorv32_config_t is
  record
    riscv_c      : boolean;
    riscv_m      : boolean;
    riscv_u      : boolean;
    riscv_zicntr : boolean;
    riscv_zihpm  : boolean;
    fast_ops     : boolean;
    pmp_nr       : natural;
    hpm_nr       : natural;
    icache_en    : boolean;
    icache_nb    : natural;
    icache_bs    : natural;
    icache_as    : natural;
    dcache_en    : boolean;
    dcache_nb    : natural;
    dcache_bs    : natural;
    mtime        : boolean;
  end record;

  constant neorv32_config_minimal_c: neorv32_config_t := (
    riscv_c => false,
    riscv_m => false,
    riscv_u => false,
    riscv_zicntr => false,
    riscv_zihpm => false,
    fast_ops => false,
    pmp_nr => 0,
    hpm_nr => 0,
    icache_en => false,
    icache_nb => 1,
    icache_bs => 4,
    icache_as => 1,
    dcache_en => false,
    dcache_nb => 1,
    dcache_bs => 4,
    mtime => false
    );

  constant neorv32_config_lite_c: neorv32_config_t := (
    riscv_c => true,
    riscv_m => true,
    riscv_u => false,
    riscv_zicntr => false,
    riscv_zihpm => false,
    fast_ops => false,
    pmp_nr => 0,
    hpm_nr => 0,
    icache_en => false,
    icache_nb => 1,
    icache_bs => 4,
    icache_as => 1,
    dcache_en => false,
    dcache_nb => 1,
    dcache_bs => 4,
    mtime => true
    );

  constant neorv32_config_standard_c: neorv32_config_t := (
    riscv_c => true,
    riscv_m => true,
    riscv_u => false,
    riscv_zicntr => true,
    riscv_zihpm => false,
    fast_ops => true,
    pmp_nr => 0,
    hpm_nr => 0,
    icache_en => true,
    icache_nb => 8,
    icache_bs => 64,
    icache_as => 1,
    dcache_en => true,
    dcache_nb => 8,
    dcache_bs => 64,
    mtime => true
    );

  constant neorv32_config_full_c: neorv32_config_t := (
    riscv_c => true,
    riscv_m => true,
    riscv_u => true,
    riscv_zicntr => true,
    riscv_zihpm => true,
    fast_ops => true,
    pmp_nr => 8,
    hpm_nr => 8,
    icache_en => true,
    icache_nb => 8,
    icache_bs => 256,
    icache_as => 2,
    dcache_en => true,
    dcache_nb => 8,
    dcache_bs => 256,
    mtime => true
    );

  -- Some default Wishbone configurations

  constant neorv32_wb_pipelined_c : wb_config_t := (
    version => WB_B4,
    bus_type => WB_CLASSIC_PIPELINED,
    adr_width => 32,
    port_size_l2 => 5,
    port_granularity_l2 => 3,
    max_op_size_l2 => 5,
    endian => WB_ENDIAN_LITTLE,
    error_supported => true,
    retry_supported => false,
    tga_width => 3,
    req_tgd_width => 0,
    ack_tgd_width => 0,
    tgc_width => 0,
    timeout => 1024,
    burst_supported => false,
    wrap_supported => false
    );

  constant neorv32_wb_standard_c : wb_config_t := (
    version => WB_B4,
    bus_type => WB_CLASSIC_STANDARD,
    adr_width => 32,
    port_size_l2 => 5,
    port_granularity_l2 => 3,
    max_op_size_l2 => 5,
    endian => WB_ENDIAN_LITTLE,
    error_supported => true,
    retry_supported => false,
    tga_width => 3,
    req_tgd_width => 0,
    ack_tgd_width => 0,
    tgc_width => 0,
    timeout => 1024,
    burst_supported => false,
    wrap_supported => false
    );
  
  -- Processor with internal boot rom (must be provided by user in a
  -- user_data.neorv32_init.neorv32_bootrom_init byte_string constant).
  --
  -- Wishbone parameters required:
  -- - version: B4
  -- - bus type: Classic (either pipelined or standard)
  -- - address width: 32 bits
  -- - data width: 32 bits
  -- - data granularity: 8 bits
  -- - address tag width: 3 bits
  --
  -- If JTAG is enabled, the DTM TAP implementation from NeoRV32
  -- project is used. IDCODE is fixed to 0x00000001.
  component neorv32_processor is
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
  end component;

end package;
