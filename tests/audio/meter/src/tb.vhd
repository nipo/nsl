library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_audio.meter.all;
use nsl_data.text.all;

-- Watches audio go by and says how loud it was.
--
-- A peak meter has two halves to it: it must follow a sample up the
-- instant one arrives, and it must come back down on its own
-- afterwards.  Both are checked here, along with the two things that
-- would make it useless -- reading a negative sample as nothing, and
-- letting one channel's level answer for another's.
--
-- It also must not touch the stream it watches, which is checked by
-- the stream here having no sink at all: nothing but the meter is
-- listening, and a beat is exchanged regardless.
entity tb is
end entity;

architecture arch of tb is

  constant sample_bits_c: natural := 24;
  -- Falls fast, so that a test does not have to run for a block of
  -- audio to see it fall.
  constant decay_l2_c: natural := 4;

  constant config_c: config_t := nsl_audio.metadata.plain_config(
    channels => 2, sample_bits => sample_bits_c);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal watched_m_s: nsl_amba.axi4_stream.master_t;
  signal watched_s_s: nsl_amba.axi4_stream.slave_t;
  signal peak_s: peak_vector(0 to 1);

  function sample_of(v: integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(v, sample_bits_c)), CODING_SIGNED);
  end function;

  function frame_of(a, b: integer) return frame_t
  is
    variable ret: frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(a);
    ret(1).sample := sample_of(b);
    return ret;
  end function;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

  watcher: nsl_audio.meter.pcm_peak_meter
    generic map(
      config_c => config_c,
      decay_l2_c => decay_l2_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      master_i => watched_m_s,
      slave_i => watched_s_s,

      peak_o => peak_s
      );

  main: process is
    variable level: integer;

    -- One beat exchanged where the meter can see it
    procedure beat(constant a, b: integer) is
    begin
      wait until falling_edge(clock_s);
      watched_m_s <= transfer(config_c, frame_of(a, b));
      watched_s_s <= accept(config_c, true);
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
      watched_m_s <= transfer_defaults(config_c);
      watched_s_s <= accept(config_c, false);
    end procedure;

    -- Beats nobody is ready for, which the meter must not count
    procedure held_back(constant a, b: integer) is
    begin
      wait until falling_edge(clock_s);
      watched_m_s <= transfer(config_c, frame_of(a, b));
      watched_s_s <= accept(config_c, false);
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
      watched_m_s <= transfer_defaults(config_c);
    end procedure;

  begin
    watched_m_s <= transfer_defaults(config_c);
    watched_s_s <= accept(config_c, false);
    done_s <= "0";

    wait until reset_n_s = '1';

    -- Nothing has gone by, so there is nothing to show.
    assert to_integer(peak_s(0)) = 0 and to_integer(peak_s(1)) = 0
      report "Meter had something to say before anything happened"
      severity failure;

    -- A sample arrives and the meter is there at once, on both
    -- channels, and a negative one counts for as much as a positive.
    beat(100000, -100000);
    assert to_integer(peak_s(0)) = 100000
      report "Meter read " & to_string(to_integer(peak_s(0)))
      & " for a sample of 100000"
      severity failure;
    assert to_integer(peak_s(1)) = 100000
      report "Meter read " & to_string(to_integer(peak_s(1)))
      & " for a sample of -100000"
      severity failure;

    -- A quieter one does not pull it down straight away.
    beat(1, -1);
    assert to_integer(peak_s(0)) > 90000
      report "Meter fell to " & to_string(to_integer(peak_s(0)))
      & " on one quiet sample"
      severity failure;

    -- But it does come down.
    for i in 1 to 16
    loop
      beat(0, 0);
    end loop;
    level := to_integer(peak_s(0));
    assert level < 50000 and level > 20000
      report "Meter sat at " & to_string(level) & " after sixteen frames"
      severity failure;

    -- All the way, rather than sticking somewhere above nothing.
    for i in 1 to 400
    loop
      beat(0, 0);
    end loop;
    assert to_integer(peak_s(0)) = 0
      report "Meter stuck at " & to_string(to_integer(peak_s(0)))
      severity failure;

    -- A beat nobody took never happened.
    held_back(4000000, 4000000);
    assert to_integer(peak_s(0)) = 0
      report "Meter counted a beat that was never exchanged"
      severity failure;

    -- One channel loud, the other silent, and the two stay apart.
    beat(2000000, 0);
    assert to_integer(peak_s(0)) = 2000000 and to_integer(peak_s(1)) = 0
      report "Meter read " & to_string(to_integer(peak_s(0))) & " and "
      & to_string(to_integer(peak_s(1)))
      severity failure;

    wait until falling_edge(clock_s);
    done_s <= "1";
    wait;
  end process;

end architecture;
