library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_hwdep, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_logic.logic.all;

-- Synthesis vehicle for the axi4_stream_packer, meant for utilization
-- and timing measurement, not for any useful on-board function.
--
-- A free-running PRBS drives the packer input with pseudo-random
-- data, user, strobe and valid, and pseudo-random backpressure is
-- applied on the output side. Every accepted output beat is
-- XOR-folded into the LED register, so no part of the packer datapath
-- is left dangling for the optimizer to trim.
entity boundary is
  port (
    done_led_o: out std_ulogic
  );
end boundary;

architecture arch of boundary is

  constant word_count_c: natural := 4;
  constant cfg_c: config_t := config(word_count_c,
                                     user => word_count_c,
                                     strobe => true);

  signal clock_s, reset_n_s: std_ulogic;
  signal in_s, out_s: bus_t;

  type regs_t is
  record
    state: prbs_state(30 downto 0);
    led: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function beat_bytes(state: prbs_state) return byte_string
  is
    variable ret: byte_string(0 to word_count_c-1);
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

  function folded(m: master_t) return std_ulogic
  is
    constant b: byte_string(0 to word_count_c-1) := bytes(cfg_c, m);
    variable ret: std_ulogic;
  begin
    ret := xor_reduce(user(cfg_c, m));
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

  packer: nsl_amba.stream_processing.axi4_stream_packer
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => in_s.m,
      in_o => in_s.s,

      out_o => out_s.m,
      out_i => out_s.s
      );

  in_s.m <= transfer(cfg_c,
                     bytes => beat_bytes(r.state),
                     strobe => std_ulogic_vector(r.state(word_count_c-1 downto 0)),
                     user => std_ulogic_vector(r.state(2*word_count_c-1 downto word_count_c)),
                     valid => r.state(2*word_count_c) = '1');

  out_s.s <= accept(cfg_c, r.state(30) = '1');

  done_led_o <= r.led;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.state <= (0 => '1', others => '0');
      r.led <= '0';
    end if;
  end process;

  transition: process(r, in_s, out_s) is
  begin
    rin <= r;

    if is_ready(cfg_c, in_s.s) then
      rin.state <= prbs_forward(r.state, prbs31, 8);
    end if;

    if is_valid(cfg_c, out_s.m) and is_ready(cfg_c, out_s.s) then
      rin.led <= r.led xor folded(out_s.m);
    end if;
  end process;

end arch;
