library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_hwdep, nsl_inet, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_inet.switching.all;
use nsl_logic.logic.all;

-- Synthesis vehicle for the ethernet switching bridge, meant for
-- utilization and timing measurement, not for any useful on-board
-- function.
--
-- One free-running PRBS per port drives data, keep, user, valid and
-- last of the bridge input with pseudo-random values, another
-- pseudo-random word drives the flood mask, and pseudo-random
-- backpressure is applied on every output port. Every output beat
-- field is XOR-folded into the LED register each cycle, so no part of
-- the bridge is left dangling for the optimizer to trim.
entity boundary is
  port (
    done_led_o: out std_ulogic
  );
end boundary;

architecture arch of boundary is

  constant port_count_c: natural := 4;
  constant byte_count_c: natural := 4;
  constant cfg_c: config_t := config(byte_count => byte_count_c,
                                     port_count => port_count_c,
                                     buffer_bytes_l2 => 11,
                                     table_entry_count_l2 => 6,
                                     table_way_count => 2,
                                     learning_enabled => true,
                                     age_time_l2 => 20);
  constant stream_cfg_c: nsl_amba.axi4_stream.config_t := port_config(cfg_c);

  signal clock_s, reset_n_s: std_ulogic;
  signal in_m_s, out_m_s: nsl_amba.axi4_stream.master_vector(0 to port_count_c-1);
  signal in_s_s, out_s_s: nsl_amba.axi4_stream.slave_vector(0 to port_count_c-1);
  signal flood_mask_s: port_mask_t;

  type prbs_state_vector is array(0 to port_count_c-1) of prbs_state(30 downto 0);

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
      stream_cfg_c,
      bytes => beat_bytes(state),
      keep => std_ulogic_vector(state(byte_count_c-1 downto 0)),
      user => std_ulogic_vector(state(byte_count_c downto byte_count_c)),
      valid => state(byte_count_c+1) = '1',
      last => state(byte_count_c+2) = '1');
  end function;

  function folded(m: nsl_amba.axi4_stream.master_t) return std_ulogic
  is
    constant b: byte_string(0 to byte_count_c-1)
      := nsl_amba.axi4_stream.bytes(stream_cfg_c, m);
    variable ret: std_ulogic;
  begin
    ret := xor_reduce(nsl_amba.axi4_stream.keep(stream_cfg_c, m))
      xor xor_reduce(nsl_amba.axi4_stream.user(stream_cfg_c, m))
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

  bridge: nsl_inet.switching.switching_bridge
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      flood_mask_i => flood_mask_s,

      in_i => in_m_s,
      in_o => in_s_s,

      out_o => out_m_s,
      out_i => out_s_s
      );

  stim: for i in 0 to port_count_c-1 generate
    in_m_s(i) <= stimulus(r.state(i));
    out_s_s(i) <= nsl_amba.axi4_stream.accept(stream_cfg_c,
                                              r.state(i)(30) = '1');
  end generate;

  masking: process(r) is
  begin
    flood_mask_s <= (others => '0');
    for i in 0 to port_count_c-1
    loop
      flood_mask_s(i) <= r.state(0)(20 + i);
    end loop;
  end process;

  done_led_o <= r.led;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      for i in 0 to port_count_c-1
      loop
        r.state(i) <= seed(i);
      end loop;
      r.led <= '0';
    end if;
  end process;

  transition: process(r, in_s_s, out_m_s) is
    variable led_v: std_ulogic;
  begin
    rin <= r;

    led_v := r.led;
    for i in 0 to port_count_c-1
    loop
      rin.state(i) <= prbs_forward(r.state(i), prbs31, 8);
      led_v := led_v xor folded(out_m_s(i)) xor in_s_s(i).ready;
    end loop;
    rin.led <= led_v;
  end process;

end arch;
