library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_audio.routing.all;
use nsl_data.text.all;

-- Takes channels out of a frame and puts them back somewhere else.
--
-- Three of the shapes a chain needs: a stereo input narrowed to the
-- one channel an instrument is plugged into, a mono chain widened to
-- both sides of an output, and a swap, which is the case where
-- nothing about the stream changes but everything about the frame
-- does.
--
-- What must survive all three is the framing: a beat that closed a
-- packet still closes one, and a handshake is the handshake of the
-- stream it came from.
entity tb is
end entity;

architecture arch of tb is

  constant sample_bits_c: natural := 24;

  constant stereo_c: config_t := nsl_audio.metadata.plain_config(
    channels => 2, sample_bits => sample_bits_c);
  constant mono_c: config_t := nsl_audio.metadata.plain_config(
    channels => 1, sample_bits => sample_bits_c);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pick_in_m_s, pick_out_m_s: nsl_amba.axi4_stream.master_t;
  signal pick_in_s_s, pick_out_s_s: nsl_amba.axi4_stream.slave_t;

  signal spread_in_m_s, spread_out_m_s: nsl_amba.axi4_stream.master_t;
  signal spread_in_s_s, spread_out_s_s: nsl_amba.axi4_stream.slave_t;

  signal swap_in_m_s, swap_out_m_s: nsl_amba.axi4_stream.master_t;
  signal swap_in_s_s, swap_out_s_s: nsl_amba.axi4_stream.slave_t;

  function sample_of(v: integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(v, sample_bits_c)), CODING_SIGNED);
  end function;

  function number_of(f: frame_t; channel: natural) return integer
  is
  begin
    return to_integer(signed(f(channel).sample(sample_bits_c-1 downto 0)));
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

  -- What a guitar plugged into the left of a stereo input needs
  pick: nsl_audio.routing.pcm_channel_map
    generic map(
      in_config_c => stereo_c,
      out_config_c => mono_c,
      map_c => (0 => 0)
      )
    port map(
      in_i => pick_in_m_s,
      in_o => pick_in_s_s,
      out_o => pick_out_m_s,
      out_i => pick_out_s_s
      );

  -- And what comes out of it at the other end
  spread: nsl_audio.routing.pcm_channel_map
    generic map(
      in_config_c => mono_c,
      out_config_c => stereo_c,
      map_c => (0 => 0, 1 => 0)
      )
    port map(
      in_i => spread_in_m_s,
      in_o => spread_in_s_s,
      out_o => spread_out_m_s,
      out_i => spread_out_s_s
      );

  swap: nsl_audio.routing.pcm_channel_map
    generic map(
      in_config_c => stereo_c,
      out_config_c => stereo_c,
      map_c => (0 => 1, 1 => 0)
      )
    port map(
      in_i => swap_in_m_s,
      in_o => swap_in_s_s,
      out_o => swap_out_m_s,
      out_i => swap_out_s_s
      );

  main: process is
    variable stereo_frame, mono_frame, got: frame_t;
  begin
    pick_in_m_s <= transfer_defaults(stereo_c);
    spread_in_m_s <= transfer_defaults(mono_c);
    swap_in_m_s <= transfer_defaults(stereo_c);
    pick_out_s_s <= accept(mono_c, false);
    spread_out_s_s <= accept(stereo_c, false);
    swap_out_s_s <= accept(stereo_c, false);
    done_s <= "0";

    wait until reset_n_s = '1';

    stereo_frame := frame_zero_c;
    stereo_frame(0).sample := sample_of(111111);
    stereo_frame(1).sample := sample_of(-222222);

    mono_frame := frame_zero_c;
    mono_frame(0).sample := sample_of(-333333);

    -- A stereo beat narrowed to its first channel, closing a packet
    -- and in error, both of which have to arrive as well.
    pick_in_m_s <= transfer(stereo_c, stereo_frame, last => true,
                            error => true);
    pick_out_s_s <= accept(mono_c, true);
    wait for 1 ns;

    got := frame(mono_c, pick_out_m_s);
    assert is_valid(mono_c, pick_out_m_s)
      report "Narrowed beat is not valid"
      severity failure;
    assert number_of(got, 0) = 111111
      report "Narrowed beat holds " & to_string(number_of(got, 0))
      severity failure;
    assert is_last(mono_c, pick_out_m_s) and is_error(mono_c, pick_out_m_s)
      report "Narrowed beat lost its framing"
      severity failure;
    assert is_ready(stereo_c, pick_in_s_s)
      report "Readiness did not come back up the stream"
      severity failure;

    pick_out_s_s <= accept(mono_c, false);
    wait for 1 ns;
    assert not is_ready(stereo_c, pick_in_s_s)
      report "Stream took a beat nothing downstream was ready for"
      severity failure;

    -- A mono beat onto both channels
    spread_in_m_s <= transfer(mono_c, mono_frame, block_start => true);
    wait for 1 ns;

    got := frame(stereo_c, spread_out_m_s);
    assert number_of(got, 0) = -333333 and number_of(got, 1) = -333333
      report "Widened beat holds " & to_string(number_of(got, 0)) & " and "
      & to_string(number_of(got, 1))
      severity failure;
    assert is_block(stereo_c, spread_out_m_s)
      report "Widened beat lost its block start"
      severity failure;

    -- And a swap, where the stream is the same shape either side
    swap_in_m_s <= transfer(stereo_c, stereo_frame);
    wait for 1 ns;

    got := frame(stereo_c, swap_out_m_s);
    assert number_of(got, 0) = -222222 and number_of(got, 1) = 111111
      report "Swapped beat holds " & to_string(number_of(got, 0)) & " and "
      & to_string(number_of(got, 1))
      severity failure;

    -- Nothing arriving is nothing leaving
    swap_in_m_s <= transfer_defaults(stereo_c);
    wait for 1 ns;
    assert not is_valid(stereo_c, swap_out_m_s)
      report "Beat appeared where none arrived"
      severity failure;

    wait until falling_edge(clock_s);
    done_s <= "1";
    wait;
  end process;

end architecture;
