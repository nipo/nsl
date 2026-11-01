library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver, nsl_io, nsl_amba, nsl_math, nsl_data;
use nsl_math.int_ext.all;
use nsl_transceiver.lane.all;
use nsl_amba.apb.all;
use nsl_simulation.logging.all;

-- The whole measurement, from a register write to a number a person
-- can read: two lanes of a modelled quad carrying a test pattern to
-- each other, a protocol-side adapter counting what came back, and
-- an APB master doing what gatecap or a JTAG bridge would do.
--
-- The counters live on each lane's own recovered clock and are read
-- from the configuration bus's, so this is also the only place that
-- crossing is exercised at all.
entity tb is
end tb;

architecture arch of tb is

  constant lane_count_c : natural := 2;
  constant propagation_c : time := 2600 ps;

  -- Register map of nsl_transceiver.prbs.prbs_adapter.
  constant control_c : natural := 0;
  constant status_c : natural := 4;
  constant errors_c : natural := 8;
  constant words_c : natural := 12;

  function lane_base(lane : natural) return natural
  is
  begin
    return lane * 16;
  end function;

  -- Control word fields, as the package documents them.
  constant tx_prbs7_c : unsigned(31 downto 0) := x"00000001";
  constant rx_prbs7_c : unsigned(31 downto 0) := x"00000100";
  constant rx_prbs31_c : unsigned(31 downto 0) := x"00000500";
  constant force_error_c : unsigned(31 downto 0) := x"00010000";
  constant restart_c : unsigned(31 downto 0) := x"00020000";

  constant csr_config_c : nsl_amba.apb.config_t
    := nsl_transceiver.cluster.csr_config_c;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  function lane_config return nsl_transceiver.lane.config_t
  is
  begin
    return nsl_transceiver.lane.config(
      data_byte_count => 1,
      encoding => ENCODING_PRBS,
      line_rate_mbps => 1250,
      pll_index => 0,
      ref_clock_index => 0,
      user_clock_group_index => 0);
  end function;

  constant config_c : nsl_transceiver.cluster.config_t
    := nsl_transceiver.cluster.config(
      plls => (0 => (enabled => true,
                     ref_clock_index => 0,
                     ref_clock_mhz => 125,
                     target_vco_mhz => 2500)),
      refclks => (0 => (ref_clock_index => 0, ref_clock_mhz => 125),
                  1 => (ref_clock_index => 1, ref_clock_mhz => 125)),
      lanes => (0 => lane_config, 1 => lane_config),
      user_clock_group_count => 1
      );

  constant ref_clock_c : integer_vector(0 to 1)
    := (nsl_transceiver.target.clock_id("ref0"),
        nsl_transceiver.target.clock_id("stableclk"));

  signal pad_s, rx_pad_s : nsl_io.diff.diff_pair_vector(0 to lane_count_c-1);
  signal lane_clock_s, lane_rx_clock_s : std_ulogic_vector(0 to lane_count_c-1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to lane_count_c-1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to lane_count_c-1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to lane_count_c-1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to lane_count_c-1);

  signal quad_apb_clock_s : std_ulogic;
  signal quad_apb_s_s : nsl_amba.apb.slave_t;

  signal apb_m_s : nsl_amba.apb.master_t;
  signal apb_s_s : nsl_amba.apb.slave_t;

begin

  cable: for e in 0 to lane_count_c-1 generate
    rx_pad_s(e) <= transport pad_s(lane_count_c-1-e) after propagation_c;
  end generate;

  quad: nsl_transceiver.cluster.transceiver_cluster
    generic map(
      config_c => config_c,
      ref_clock_c => ref_clock_c
      )
    port map(
      reset_n_i => reset_n_s,

      ref_clock_i(0) => clock_s,
      ref_clock_i(1) => clock_s,

      lane_tx_o => pad_s,
      lane_rx_i => rx_pad_s,

      lane_tx_clock_o => lane_clock_s,
      lane_rx_clock_o => lane_rx_clock_s,

      tx_m_i => tx_m_s,
      tx_s_o => tx_s_s,
      rx_m_o => rx_m_s,
      rx_s_i => rx_s_s,

      pma_reset_n_i => (others => '1'),

      apb_clock_o => quad_apb_clock_s,
      apb_reset_n_i => reset_n_s,
      apb_m_i => nsl_amba.apb.transfer_idle(csr_config_c),
      apb_s_o => quad_apb_s_s
      );

  -- The adapter runs on the clock the quad hands out for its own
  -- configuration bus, which is not any lane's.
  monitor: nsl_transceiver.prbs.prbs_adapter
    generic map(
      config_c => csr_config_c,
      lane_count_c => lane_count_c
      )
    port map(
      clock_i => quad_apb_clock_s,
      reset_n_i => reset_n_s,
      apb_i => apb_m_s,
      apb_o => apb_s_s,

      lane_clock_i => lane_rx_clock_s,

      tx_m_o => tx_m_s,
      tx_s_i => tx_s_s,
      rx_m_i => rx_m_s,
      rx_s_o => rx_s_s
      );

  software: process
    constant ctxt : log_context := "prbs over apb";
    variable value_v : unsigned(31 downto 0);
    variable errors_v : unsigned(31 downto 0);
    variable words_v : unsigned(31 downto 0);
    variable before_v : unsigned(31 downto 0);
    variable err_v : boolean;
    variable polls_v : natural;

    procedure write_reg(addr : natural; value : unsigned) is
    begin
      -- The register map only takes writes of the whole bus width,
      -- so every byte is strobed.
      apb_write(csr_config_c, quad_apb_clock_s, apb_s_s, apb_m_s,
                to_unsigned(addr, csr_config_c.address_width), value,
                strb => "1111",
                err => err_v);
      assert not err_v
        report "the adapter refused a write to "
        & integer'image(addr)
        severity failure;
    end procedure;

    procedure read_reg(addr : natural; value : out unsigned) is
    begin
      apb_read(csr_config_c, quad_apb_clock_s, apb_s_s, apb_m_s,
               to_unsigned(addr, csr_config_c.address_width), value, err_v);
      assert not err_v
        report "the adapter refused a read of "
        & integer'image(addr)
        severity failure;
    end procedure;

    -- Waits for a lane to report the pattern found, the way software
    -- with nothing but this bus to look through would.
    procedure wait_locked(lane : natural) is
    begin
      polls_v := 0;
      loop
        read_reg(lane_base(lane) + status_c, value_v);
        exit when value_v(0) = '1';
        polls_v := polls_v + 1;
        assert polls_v < 1024
          report "lane " & integer'image(lane)
          & " never reported the pattern through its registers"
          severity failure;
      end loop;
    end procedure;
  begin
    done_s(0) <= '0';

    wait until reset_n_s = '1';

    -- Nothing is asked for yet, so nothing is found.
    read_reg(lane_base(0) + status_c, value_v);
    assert value_v(0) = '0'
      report "a lane reported a pattern before one was asked for"
      severity failure;

    -- Both lanes, both directions, order 7.
    for lane in 0 to lane_count_c-1 loop
      write_reg(lane_base(lane) + control_c, tx_prbs7_c or rx_prbs7_c);
    end loop;

    for lane in 0 to lane_count_c-1 loop
      wait_locked(lane);
    end loop;

    log_info(ctxt, "both lanes reported the pattern through their"
             & " registers");

    -- The request bits are events: they do not read back.
    read_reg(lane_base(0) + control_c, value_v);
    assert value_v = (tx_prbs7_c or rx_prbs7_c)
      report "the control register read back as "
      & integer'image(to_integer(value_v))
      severity failure;

    -- A window of words with nothing wrong in it. The counters are
    -- on the lane's clock and read from this one, so the only thing
    -- that makes this answerable is that they move one step at a
    -- time.
    read_reg(lane_base(1) + words_c, before_v);
    read_reg(lane_base(1) + errors_c, errors_v);

    for i in 0 to 255 loop
      wait until rising_edge(quad_apb_clock_s);
    end loop;

    read_reg(lane_base(1) + words_c, words_v);
    assert words_v > before_v
      report "the word counter did not move while the pattern was"
      & " being checked"
      severity failure;

    read_reg(lane_base(1) + errors_c, value_v);
    assert value_v = errors_v
      report "the error counter moved by "
      & integer'image(to_integer(value_v - errors_v))
      & " on a link nothing had touched"
      severity failure;

    log_info(ctxt, "counted "
             & integer'image(to_integer(words_v - before_v))
             & " words with no error through the bus");

    -- One bit spoiled on the far side has to arrive as exactly one
    -- more error here.
    read_reg(lane_base(1) + errors_c, before_v);
    write_reg(lane_base(0) + control_c,
              tx_prbs7_c or rx_prbs7_c or force_error_c);

    for i in 0 to 255 loop
      wait until rising_edge(quad_apb_clock_s);
    end loop;

    read_reg(lane_base(1) + errors_c, value_v);
    assert value_v = before_v + 1
      report "a single spoiled bit moved the error counter by "
      & integer'image(to_integer(value_v - before_v))
      severity failure;

    log_info(ctxt, "a spoiled bit arrived as exactly one error");

    -- Pointed at the wrong pattern, a lane has to stop reporting the
    -- one it had.
    write_reg(lane_base(1) + control_c, tx_prbs7_c or rx_prbs31_c);

    polls_v := 0;
    loop
      read_reg(lane_base(1) + status_c, value_v);
      exit when value_v(0) = '0';
      polls_v := polls_v + 1;
      assert polls_v < 1024
        report "a lane kept reporting a pattern it was no longer"
        & " looking for"
        severity failure;
    end loop;

    log_info(ctxt, "gave up the pattern when pointed at another");

    -- And comes back when asked again.
    write_reg(lane_base(1) + control_c,
              tx_prbs7_c or rx_prbs7_c or restart_c);
    wait_locked(1);

    log_info(ctxt, "found it again after a restart");

    -- A lane the map does not have is answered, not left to stall.
    apb_read(csr_config_c, quad_apb_clock_s, apb_s_s, apb_m_s,
             to_unsigned(lane_base(lane_count_c) + status_c,
                         csr_config_c.address_width),
             value_v, err_v);
    assert err_v
      report "the adapter answered for a lane it does not have"
      severity failure;

    log_info(ctxt, "refused a lane outside its map");

    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 20 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
