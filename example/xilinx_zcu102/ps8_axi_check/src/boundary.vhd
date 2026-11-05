library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_xilinx;

entity boundary is
  port(
    ld_o: out std_ulogic_vector(0 to 7)
    );
end entity;

architecture beh of boundary is

  constant lpd_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 12, data_bus_width => 32,
                               id_width => 16, max_length => 256,
                               size => true, burst => true);
  constant apb_config_c : nsl_amba.apb.config_t
    := nsl_amba.apb.config(address_width => 12, data_bus_width => 32,
                           strb => true);
  constant fpd_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 12, data_bus_width => 64,
                               id_width => 16, max_length => 256,
                               size => true, burst => true);

  constant s_lpd_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 128,
                               max_length => 16,
                               size => true, burst => true);
  constant hpc0_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 64,
                               max_length => 16,
                               size => true, burst => true);
  constant hp0_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32,
                               max_length => 16,
                               size => true, burst => true);
  constant hpc1_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 128,
                               max_length => 16,
                               size => true, burst => true);

  -- S_AXI_LPD, S_AXI_HPC0 and S_AXI_HP0 regions are in OCM.  The
  -- S_AXI_HPC1 region is the RAM behind M_AXI_HPM0_FPD.
  constant ocm_region_byte_l2_c : natural := 16;
  constant s_lpd_base_c : unsigned(31 downto 0) := x"FFFC0000";
  constant hpc0_base_c : unsigned(31 downto 0) := x"FFFD0000";
  constant hp0_base_c : unsigned(31 downto 0) := x"FFFE0000";
  constant ram_byte_l2_c : natural := 12;
  constant fpd_loop_base_c : unsigned(31 downto 0) := x"A0000000";
  constant burst_length_c : natural := 8;

  constant port_count_c : natural := 4;

  type tester_t is
  record
    busy, done: std_ulogic;
    error_count: unsigned(31 downto 0);
    first_error: unsigned(31 downto 0);
  end record;

  type tester_vector is array (natural range <>) of tester_t;

  type cycles_vector is array (natural range <>) of unsigned(31 downto 0);

  type regs_t is
  record
    enable, start: std_ulogic_vector(0 to port_count_c-1);
    cycles: cycles_vector(0 to port_count_c-1);
    heartbeat: unsigned(25 downto 0);
  end record;

  signal r, rin: regs_t;

  signal pl_clock_s, pl_reset_n_s : std_ulogic_vector(0 to 3);
  signal clock_s, reset_n_s : std_ulogic;
  signal tester_reset_n_s : std_ulogic_vector(0 to port_count_c-1);
  signal tester_s : tester_vector(0 to port_count_c-1);

  signal lpd_m_s, fpd_m_s, s_lpd_m_s, hpc0_m_s, hp0_m_s, hpc1_m_s : nsl_amba.axi4_mm.master_t;
  signal lpd_s_s, fpd_s_s, s_lpd_s_s, hpc0_s_s, hp0_s_s, hpc1_s_s : nsl_amba.axi4_mm.slave_t;
  signal apb_m_s : nsl_amba.apb.master_t;
  signal apb_s_s : nsl_amba.apb.slave_t;

  signal reg_no_s : integer range 0 to 15;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s : std_ulogic;

begin

  clock_s <= pl_clock_s(0);

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => pl_reset_n_s(0),
      data_o => reset_n_s
      );

  ps: nsl_xilinx.ps8.ps8_wrapper
    generic map(
      m_axi_hpm0_lpd_config_c => lpd_config_c,
      m_axi_hpm0_fpd_config_c => fpd_config_c,
      s_axi_lpd_config_c => s_lpd_config_c,
      s_axi_hpc0_fpd_config_c => hpc0_config_c,
      s_axi_hp0_fpd_config_c => hp0_config_c,
      s_axi_hpc1_fpd_config_c => hpc1_config_c
      )
    port map(
      pl_clock_o => pl_clock_s,
      pl_reset_n_o => pl_reset_n_s,

      m_axi_hpm0_lpd_clock_i => clock_s,
      m_axi_hpm0_lpd_o => lpd_m_s,
      m_axi_hpm0_lpd_i => lpd_s_s,

      m_axi_hpm0_fpd_clock_i => clock_s,
      m_axi_hpm0_fpd_o => fpd_m_s,
      m_axi_hpm0_fpd_i => fpd_s_s,

      s_axi_lpd_clock_i => clock_s,
      s_axi_lpd_i => s_lpd_m_s,
      s_axi_lpd_o => s_lpd_s_s,

      s_axi_hpc0_fpd_clock_i => clock_s,
      s_axi_hpc0_fpd_i => hpc0_m_s,
      s_axi_hpc0_fpd_o => hpc0_s_s,

      s_axi_hp0_fpd_clock_i => clock_s,
      s_axi_hp0_fpd_i => hp0_m_s,
      s_axi_hp0_fpd_o => hp0_s_s,

      s_axi_hpc1_fpd_clock_i => clock_s,
      s_axi_hpc1_fpd_i => hpc1_m_s,
      s_axi_hpc1_fpd_o => hpc1_s_s
      );

  ram: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => fpd_config_c,
      byte_size_l2_c => ram_byte_l2_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_i => fpd_m_s,
      axi_o => fpd_s_s
      );

  bridge: nsl_amba.axi_apb.axi4_apb_bridge
    generic map(
      axi_config_c => lpd_config_c,
      apb_config_c => apb_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      irq_n_o => open,
      axi_i => lpd_m_s,
      axi_o => lpd_s_s,
      apb_o => apb_m_s,
      apb_i => apb_s_s
      );

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => apb_config_c,
      reg_count_l2_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      apb_i => apb_m_s,
      apb_o => apb_s_s,
      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => open
      );

  testers: for i in 0 to port_count_c-1
  generate
    tester_reset_n_s(i) <= reset_n_s and r.enable(i);
  end generate;

  s_lpd_tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => s_lpd_config_c,
      base_address_c => s_lpd_base_c,
      region_byte_l2_c => ocm_region_byte_l2_c,
      burst_length_c => burst_length_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => tester_reset_n_s(0),
      start_i => r.start(0),
      axi_o => s_lpd_m_s,
      axi_i => s_lpd_s_s,
      busy_o => tester_s(0).busy,
      done_o => tester_s(0).done,
      error_count_o => tester_s(0).error_count,
      first_error_address_o => tester_s(0).first_error
      );

  hpc0_tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => hpc0_config_c,
      base_address_c => hpc0_base_c,
      region_byte_l2_c => ocm_region_byte_l2_c,
      burst_length_c => burst_length_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => tester_reset_n_s(1),
      start_i => r.start(1),
      axi_o => hpc0_m_s,
      axi_i => hpc0_s_s,
      busy_o => tester_s(1).busy,
      done_o => tester_s(1).done,
      error_count_o => tester_s(1).error_count,
      first_error_address_o => tester_s(1).first_error
      );

  hp0_tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => hp0_config_c,
      base_address_c => hp0_base_c,
      region_byte_l2_c => ocm_region_byte_l2_c,
      burst_length_c => burst_length_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => tester_reset_n_s(2),
      start_i => r.start(2),
      axi_o => hp0_m_s,
      axi_i => hp0_s_s,
      busy_o => tester_s(2).busy,
      done_o => tester_s(2).done,
      error_count_o => tester_s(2).error_count,
      first_error_address_o => tester_s(2).first_error
      );

  fpd_loop_tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => hpc1_config_c,
      base_address_c => fpd_loop_base_c,
      region_byte_l2_c => ram_byte_l2_c,
      burst_length_c => burst_length_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => tester_reset_n_s(3),
      start_i => r.start(3),
      axi_o => hpc1_m_s,
      axi_i => hpc1_s_s,
      busy_o => tester_s(3).busy,
      done_o => tester_s(3).done,
      error_count_o => tester_s(3).error_count,
      first_error_address_o => tester_s(3).first_error
      );

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.enable <= (others => '0');
      r.start <= (others => '0');
      r.cycles <= (others => (others => '0'));
    end if;
  end process;

  -- Register map, 32-bit words:
  -- 0: control, enable at bit i, start at bit 8+i
  -- 1: status, busy at bit 2*i, done at bit 2*i+1
  -- 2+3*i: error count of port i
  -- 3+3*i: first error address of port i
  -- 4+3*i: clock cycles port i was busy
  transition: process(r, reg_no_s, w_value_s, w_strobe_s, tester_s) is
  begin
    rin <= r;

    rin.heartbeat <= r.heartbeat + 1;

    for i in 0 to port_count_c-1
    loop
      if tester_s(i).busy = '1' then
        rin.cycles(i) <= r.cycles(i) + 1;
      end if;

      if r.enable(i) = '0' then
        rin.cycles(i) <= (others => '0');
      end if;
    end loop;

    if w_strobe_s = '1' and reg_no_s = 0 then
      for i in 0 to port_count_c-1
      loop
        rin.enable(i) <= w_value_s(i);
        rin.start(i) <= w_value_s(8+i);
      end loop;
    end if;
  end process;

  mealy: process(r, reg_no_s, tester_s) is
    variable port_no : natural range 0 to port_count_c-1;
  begin
    r_value_s <= (others => '0');

    case reg_no_s is
      when 0 =>
        for i in 0 to port_count_c-1
        loop
          r_value_s(i) <= r.enable(i);
          r_value_s(8+i) <= r.start(i);
        end loop;

      when 1 =>
        for i in 0 to port_count_c-1
        loop
          r_value_s(2*i) <= tester_s(i).busy;
          r_value_s(2*i+1) <= tester_s(i).done;
        end loop;

      when 2 to 1 + 3 * port_count_c =>
        port_no := (reg_no_s - 2) / 3;
        case (reg_no_s - 2) mod 3 is
          when 0 => r_value_s <= tester_s(port_no).error_count;
          when 1 => r_value_s <= tester_s(port_no).first_error;
          when others => r_value_s <= r.cycles(port_no);
        end case;

      when others =>
        null;
    end case;
  end process;

  leds: for i in 0 to port_count_c-1
  generate
    ld_o(i) <= tester_s(i).done when tester_s(i).error_count = 0 else '0';
  end generate;

  ld_o(4) <= reset_n_s;
  ld_o(5) <= '0';
  ld_o(6) <= '0';
  ld_o(7) <= r.heartbeat(r.heartbeat'left);

end architecture;
