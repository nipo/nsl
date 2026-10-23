library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_xilinx;

entity boundary is
  port(
    clock_125_i: in std_ulogic;

    ld_o: out std_ulogic_vector(0 to 3)
    );
end entity;

architecture beh of boundary is

  constant gp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 12, data_bus_width => 32,
                               id_width => 12, max_length => 16,
                               size => true, burst => true);
  constant apb_config_c : nsl_amba.apb.config_t
    := nsl_amba.apb.config(address_width => 12, data_bus_width => 32,
                           strb => true);

  -- Testers only use ID 0, the crossbar adds one bit for the master
  -- index.
  constant tester_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 64,
                               id_width => 1, max_length => 16,
                               size => true, burst => true);
  constant hp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 64,
                               id_width => 2, max_length => 16,
                               size => true, burst => true);

  constant routing_table_c : nsl_amba.address.address_vector
    := nsl_amba.address.routing_table(32, "x00000000/0");

  constant crossbar_slice_c : boolean := true;

  -- Each tester walks its own 16 MB of DDR, from 256 MB up, clear of
  -- whatever the boot software uses.
  constant region_byte_l2_c : natural := 24;
  constant region_base_c : natural := 16#10000000#;
  constant burst_length_c : natural := 16;
  constant outstanding_c : positive := 8;

  -- Testers 0 and 1 share S_AXI_HP0 through the crossbar, testers 2
  -- and 3 have S_AXI_HP1 and S_AXI_HP2 to themselves.
  constant tester_count_c : natural := 4;

  type tester_t is
  record
    busy, writing, done: std_ulogic;
    error_count: unsigned(31 downto 0);
    first_error: unsigned(31 downto 0);
  end record;

  type tester_vector is array (natural range <>) of tester_t;

  type cycles_vector is array (natural range <>) of unsigned(31 downto 0);

  type regs_t is
  record
    enable, start: std_ulogic_vector(0 to tester_count_c-1);
    write_cycles, read_cycles: cycles_vector(0 to tester_count_c-1);
  end record;

  signal r, rin: regs_t;

  signal clock_s, startup_reset_n_s, reset_n_s : std_ulogic;
  signal tester_reset_n_s, port_reset_n_s : std_ulogic_vector(0 to tester_count_c-1);
  signal tester_s : tester_vector(0 to tester_count_c-1);
  signal tester_m_s : nsl_amba.axi4_mm.master_vector(0 to tester_count_c-1);
  signal tester_s_s : nsl_amba.axi4_mm.slave_vector(0 to tester_count_c-1);

  signal gp1_reset_n_s : std_ulogic;
  signal gp1_m_s, hp0_m_s : nsl_amba.axi4_mm.master_t;
  signal gp1_s_s, hp0_s_s : nsl_amba.axi4_mm.slave_t;
  signal apb_m_s : nsl_amba.apb.master_t;
  signal apb_s_s : nsl_amba.apb.slave_t;

  signal reg_no_s : integer range 0 to 31;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s : std_ulogic;

begin

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_125_i,
      clock_o => clock_s
      );

  startup_reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => startup_reset_n_s
      );

  reset_n_s <= startup_reset_n_s and gp1_reset_n_s;

  ps: nsl_xilinx.ps7.ps7_wrapper
    generic map(
      m_axi_gp1_config_c => gp_config_c,
      s_axi_hp0_config_c => hp_config_c,
      s_axi_hp1_config_c => hp_config_c,
      s_axi_hp2_config_c => hp_config_c
      )
    port map(
      fclk_o => open,
      fclk_reset_n_o => open,

      m_axi_gp1_clock_i => clock_s,
      m_axi_gp1_reset_n_o => gp1_reset_n_s,
      m_axi_gp1_o => gp1_m_s,
      m_axi_gp1_i => gp1_s_s,

      s_axi_hp0_clock_i => clock_s,
      s_axi_hp0_reset_n_o => port_reset_n_s(0),
      s_axi_hp0_i => hp0_m_s,
      s_axi_hp0_o => hp0_s_s,

      s_axi_hp1_clock_i => clock_s,
      s_axi_hp1_reset_n_o => port_reset_n_s(2),
      s_axi_hp1_i => tester_m_s(2),
      s_axi_hp1_o => tester_s_s(2),

      s_axi_hp2_clock_i => clock_s,
      s_axi_hp2_reset_n_o => port_reset_n_s(3),
      s_axi_hp2_i => tester_m_s(3),
      s_axi_hp2_o => tester_s_s(3)
      );

  port_reset_n_s(1) <= port_reset_n_s(0);

  crossbar: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => tester_config_c,
      slave_config_c => hp_config_c,
      master_count_c => 2,
      routing_table_c => routing_table_c,
      default_slave_c => 0,
      aw_tracking_depth_c => outstanding_c,
      max_outstanding_c => outstanding_c,
      master_slice_c => crossbar_slice_c,
      slave_slice_c => crossbar_slice_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => port_reset_n_s(0),
      slave_i => tester_m_s(0 to 1),
      slave_o => tester_s_s(0 to 1),
      master_o(0) => hp0_m_s,
      master_i(0) => hp0_s_s
      );

  bridge: nsl_amba.axi_apb.axi4_apb_bridge
    generic map(
      axi_config_c => gp_config_c,
      apb_config_c => apb_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      irq_n_o => open,
      axi_i => gp1_m_s,
      axi_o => gp1_s_s,
      apb_o => apb_m_s,
      apb_i => apb_s_s
      );

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => apb_config_c,
      reg_count_l2_c => 5
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

  testers: for i in 0 to tester_count_c-1
  generate
    tester_reset_n_s(i) <= port_reset_n_s(i) and r.enable(i);

    tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
      generic map(
        config_c => tester_config_c,
        base_address_c => region_base_c + i * 2 ** region_byte_l2_c,
        region_byte_l2_c => region_byte_l2_c,
        burst_length_c => burst_length_c,
        seed_c => i + 1,
        outstanding_c => outstanding_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => tester_reset_n_s(i),
        start_i => r.start(i),
        axi_o => tester_m_s(i),
        axi_i => tester_s_s(i),
        busy_o => tester_s(i).busy,
        writing_o => tester_s(i).writing,
        done_o => tester_s(i).done,
        error_count_o => tester_s(i).error_count,
        first_error_address_o => tester_s(i).first_error
        );
  end generate;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.enable <= (others => '0');
      r.start <= (others => '0');
      r.write_cycles <= (others => (others => '0'));
      r.read_cycles <= (others => (others => '0'));
    end if;
  end process;

  -- Register map, 32-bit words:
  -- 0: control, enable at bit i, start at bit 8+i
  -- 1: status, busy at bit 2*i, done at bit 2*i+1
  -- 2+4*i: error count of tester i
  -- 3+4*i: first error address of tester i
  -- 4+4*i: clock cycles tester i spent writing
  -- 5+4*i: clock cycles tester i spent reading
  transition: process(r, reg_no_s, w_value_s, w_strobe_s, tester_s) is
  begin
    rin <= r;

    for i in 0 to tester_count_c-1
    loop
      if tester_s(i).busy = '1' then
        if tester_s(i).writing = '1' then
          rin.write_cycles(i) <= r.write_cycles(i) + 1;
        else
          rin.read_cycles(i) <= r.read_cycles(i) + 1;
        end if;
      end if;

      if r.enable(i) = '0' then
        rin.write_cycles(i) <= (others => '0');
        rin.read_cycles(i) <= (others => '0');
      end if;
    end loop;

    if w_strobe_s = '1' and reg_no_s = 0 then
      for i in 0 to tester_count_c-1
      loop
        rin.enable(i) <= w_value_s(i);
        rin.start(i) <= w_value_s(8+i);
      end loop;
    end if;
  end process;

  mealy: process(r, reg_no_s, tester_s) is
    variable tester_no : natural range 0 to tester_count_c-1;
  begin
    r_value_s <= (others => '0');

    case reg_no_s is
      when 0 =>
        for i in 0 to tester_count_c-1
        loop
          r_value_s(i) <= r.enable(i);
          r_value_s(8+i) <= r.start(i);
        end loop;

      when 1 =>
        for i in 0 to tester_count_c-1
        loop
          r_value_s(2*i) <= tester_s(i).busy;
          r_value_s(2*i+1) <= tester_s(i).done;
        end loop;

      when 2 to 1 + 4 * tester_count_c =>
        tester_no := (reg_no_s - 2) / 4;
        case (reg_no_s - 2) mod 4 is
          when 0 => r_value_s <= tester_s(tester_no).error_count;
          when 1 => r_value_s <= tester_s(tester_no).first_error;
          when 2 => r_value_s <= r.write_cycles(tester_no);
          when others => r_value_s <= r.read_cycles(tester_no);
        end case;

      when others =>
        null;
    end case;
  end process;

  leds: for i in 0 to tester_count_c-1
  generate
    ld_o(i) <= tester_s(i).done when tester_s(i).error_count = 0 else '0';
  end generate;

end architecture;
