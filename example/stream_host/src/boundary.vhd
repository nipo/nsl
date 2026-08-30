library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_hwdep, nsl_inet, nsl_logic, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_logic.logic.all;
use nsl_math.int_ext.all;
use nsl_inet.mac.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream.all;
use nsl_inet.stream_host.all;

-- Synthesis vehicle for the AXI4-Stream IPv4 host, meant for
-- utilization and timing measurement, not for any useful on-board
-- function.
--
-- The host runs at the 4-byte stream width with two UDP ports.  One
-- free-running PRBS drives the wire-side receive stream, one drives
-- each application transmit pipe, and pseudo-random backpressure is
-- applied on the wire-side transmit and both application receive
-- pipes.  Every output beat field is XOR-folded into the LED
-- register each cycle, so no part of the host is left dangling for
-- the optimizer to trim.
entity boundary is
  port (
    done_led_o: out std_ulogic
  );
end boundary;

architecture arch of boundary is

  constant byte_count_c: natural := 4;
  constant cfg_c: nsl_amba.axi4_stream.config_t := stream_config(byte_count_c);
  constant ports_c: integer_vector(0 to 1) := (1234, 5353);
  constant l1_null_c: byte_string(1 to 0) := (others => x"00");

  signal clock_s, reset_n_s: std_ulogic;
  signal l1_rx_m_s, l1_tx_m_s: nsl_amba.axi4_stream.master_t;
  signal l1_rx_s_s, l1_tx_s_s: nsl_amba.axi4_stream.slave_t;
  signal to_app_m_s: nsl_amba.axi4_stream.master_vector(0 to 1);
  signal to_app_s_s: nsl_amba.axi4_stream.slave_vector(0 to 1);
  signal from_app_m_s: nsl_amba.axi4_stream.master_vector(0 to 1);
  signal from_app_s_s: nsl_amba.axi4_stream.slave_vector(0 to 1);

  type prbs_state_vector is array(0 to 2) of prbs_state(30 downto 0);

  type regs_t is
  record
    state: prbs_state_vector;
    led: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function seed(index: natural) return prbs_state
  is
    variable ret: prbs_state(30 downto 0) := (others => '0');
  begin
    ret(index) := '1';
    ret(index + 8) := '1';
    return ret;
  end function;

  function beat_bytes(state: prbs_state) return byte_string
  is
    variable ret: byte_string(0 to byte_count_c-1);
  begin
    for i in ret'range
    loop
      for j in 0 to 7
      loop
        ret(i)(j) := state((i * 11 + j * 3) mod state'length);
      end loop;
    end loop;
    return ret;
  end function;

  function stimulus(state: prbs_state) return nsl_amba.axi4_stream.master_t
  is
  begin
    return nsl_amba.axi4_stream.transfer(
      cfg_c,
      bytes => beat_bytes(state),
      keep => std_ulogic_vector(state(byte_count_c-1 downto 0)),
      user => std_ulogic_vector(state(byte_count_c downto byte_count_c)),
      valid => state(byte_count_c+1) = '1',
      last => state(byte_count_c+2) = '1');
  end function;

  function folded(m: nsl_amba.axi4_stream.master_t) return std_ulogic
  is
    constant b: byte_string(0 to byte_count_c-1)
      := nsl_amba.axi4_stream.bytes(cfg_c, m);
    variable ret: std_ulogic;
  begin
    ret := xor_reduce(nsl_amba.axi4_stream.keep(cfg_c, m))
      xor xor_reduce(nsl_amba.axi4_stream.user(cfg_c, m))
      xor m.valid xor m.last;
    for i in b'range
    loop
      ret := ret xor xor_reduce(b(i));
    end loop;
    return ret;
  end function;

begin

  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  host: nsl_inet.stream_host.stream_ipv4_host
    generic map(
      config_c => cfg_c,
      udp_port_c => ports_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      local_hwaddr_i => from_hex("0221cafedeca"),
      local_address_i => to_ipv4(10, 0, 0, 1),

      l1_header_i => l1_null_c,

      l1_rx_i => l1_rx_m_s,
      l1_rx_o => l1_rx_s_s,
      l1_tx_o => l1_tx_m_s,
      l1_tx_i => l1_tx_s_s,

      to_app_o => to_app_m_s,
      to_app_i => to_app_s_s,
      from_app_i => from_app_m_s,
      from_app_o => from_app_s_s
      );

  l1_rx_m_s <= stimulus(r.state(0));
  l1_tx_s_s <= nsl_amba.axi4_stream.accept(cfg_c, r.state(0)(30) = '1');

  app_stim: for i in 0 to 1 generate
    from_app_m_s(i) <= stimulus(r.state(1 + i));
    to_app_s_s(i) <= nsl_amba.axi4_stream.accept(cfg_c,
                                                 r.state(1 + i)(30) = '1');
  end generate;

  done_led_o <= r.led;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      for i in r.state'range
      loop
        r.state(i) <= seed(i);
      end loop;
      r.led <= '0';
    end if;
  end process;

  transition: process(r, l1_rx_s_s, l1_tx_m_s, to_app_m_s, from_app_s_s) is
    variable led_v: std_ulogic;
  begin
    rin <= r;

    led_v := r.led xor folded(l1_tx_m_s) xor l1_rx_s_s.ready;
    for i in 0 to 1
    loop
      rin.state(1 + i) <= prbs_forward(r.state(1 + i), prbs31, 8);
      led_v := led_v xor folded(to_app_m_s(i)) xor from_app_s_s(i).ready;
    end loop;
    rin.state(0) <= prbs_forward(r.state(0), prbs31, 8);
    rin.led <= led_v;
  end process;

end arch;
