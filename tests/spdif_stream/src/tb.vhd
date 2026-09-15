library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spdif, nsl_audio, nsl_amba, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_audio.metadata.all;
use nsl_spdif.serdes.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Sends a stream out as IEC 60958 subframes and reads it back.
--
-- The whole subframe makes the trip, not just its sample: V, U and C
-- go out beside the audio and have to come back beside the same
-- sample.  Blocks have to land where they were sent, too -- a link
-- states them and a packet is one, so a boundary arriving anywhere
-- else would mean the two ends disagree about what a block is.
--
-- Parity is the one thing not checked for coming back, because it does
-- not travel: each link works it out for itself.
entity tb is
end entity;

architecture arch of tb is

  constant cfg_c: config_t := nsl_spdif.stream.framed_config;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal in_m_s, out_m_s: nsl_amba.axi4_stream.master_t;
  signal in_s_s, out_s_s: nsl_amba.axi4_stream.slave_t;

  signal tx_ready_s, tx_block_start_s, tx_channel_s: std_ulogic;
  signal tx_frame_s: nsl_spdif.framer.frame_t;
  signal underflow_s, overflow_s: std_ulogic;

  signal symbol_s, symbol_rx_s: nsl_spdif.serdes.spdif_symbol_t;
  signal corrupt_s: boolean := false;
  -- Set once the link has been seen working, so that what follows is
  -- a link being broken rather than one starting
  signal armed_s, caught_s, fired_s: boolean := false;

  signal rx_valid_s, rx_block_start_s, rx_channel_s, rx_parity_s: std_ulogic;
  signal rx_frame_s: nsl_spdif.framer.frame_t;
  signal rx_synced_s: std_ulogic;

  signal got_s: natural;

  function pat_v(ch, idx: natural) return std_ulogic is
  begin
    if ((idx + ch * 3) mod 5) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_u(ch, idx: natural) return std_ulogic is
  begin
    if ((idx + ch) mod 3) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_c(ch, idx: natural) return std_ulogic is
  begin
    if ((idx * 2 + ch) mod 7) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_frame(idx: natural) return frame_t is
    variable ret: frame_t := frame_zero_c;
  begin
    for ch in 0 to 1
    loop
      ret(ch).sample := to_sample(
        to_unsigned((idx * 4 + ch * 1000) mod 65536, cfg_c.sample_bits),
        cfg_c.coding);
      ret(ch).sideband(sideband_v_c) := pat_v(ch, idx);
      ret(ch).sideband(sideband_u_c) := pat_u(ch, idx);
      ret(ch).sideband(sideband_c_c) := pat_c(ch, idx);
    end loop;
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

  feeder: nsl_spdif.stream.spdif_stream_transmitter
    generic map(
      config_c => cfg_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => in_m_s,
      in_o => in_s_s,

      ready_i => tx_ready_s,
      block_start_o => tx_block_start_s,
      channel_o => tx_channel_s,
      frame_o => tx_frame_s,

      underflow_o => underflow_s
      );

  framer: nsl_spdif.framer.spdif_framer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      block_start_i => tx_block_start_s,
      channel_i => tx_channel_s,
      frame_i => tx_frame_s,
      ready_o => tx_ready_s,

      symbol_o => symbol_s,
      ready_i => '1'
      );

  unframer: nsl_spdif.framer.spdif_unframer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      symbol_i => symbol_rx_s,
      synced_i => '1',
      valid_i => '1',

      synced_o => rx_synced_s,
      block_start_o => rx_block_start_s,
      channel_o => rx_channel_s,
      frame_o => rx_frame_s,
      parity_ok_o => rx_parity_s,
      valid_o => rx_valid_s
      );

  gatherer: nsl_spdif.stream.spdif_stream_receiver
    generic map(
      config_c => cfg_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      valid_i => rx_valid_s,
      block_start_i => rx_block_start_s,
      channel_i => rx_channel_s,
      frame_i => rx_frame_s,
      parity_ok_i => rx_parity_s,

      out_o => out_m_s,
      out_i => out_s_s,

      overflow_o => overflow_s
      );

  out_s_s <= accept(cfg_c, true);

  -- One data bit flipped, which changes the count of ones in exactly
  -- one subframe and nothing else
  symbol_rx_s <= nsl_spdif.serdes.SPDIF_1 when corrupt_s else symbol_s;

  -- The unframer takes in what is on the wire during a cycle at the
  -- edge closing it, so the symbol to break is the one standing now,
  -- not the one that stood when a process last looked.
  corrupt_s <= armed_s and not fired_s and symbol_s = SPDIF_0;

  breaker: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if corrupt_s then
        fired_s <= true;
      end if;
    end if;

    if reset_n_s = '0' then
      fired_s <= false;
    end if;
  end process;

  -- Blocks of frames in
  source: process is
  begin
    in_m_s <= transfer_defaults(cfg_c);

    wait until reset_n_s = '1';

    loop
      for i in 0 to block_frame_count_c-1
      loop
        in_m_s <= transfer(cfg_c, pat_frame(i),
                           last => i = block_frame_count_c-1,
                           block_start => i = 0);

        loop
          wait until rising_edge(clock_s);
          exit when is_taken(cfg_c, in_m_s, in_s_s);
        end loop;
      end loop;
    end loop;
  end process;

  -- And the same blocks out
  sink: process is
    variable f: frame_t;
    variable i: natural;
    variable packets: natural := 0;
  begin
    got_s <= 0;

    -- Start where the link says a block does, then hold everything
    -- after it to the place it should be
    loop
      wait until rising_edge(clock_s) and is_taken(cfg_c, out_m_s, out_s_s);
      exit when is_block(cfg_c, out_m_s);
    end loop;

    f := frame(cfg_c, out_m_s);
    i := 0;

    loop
      if not armed_s then
        assert f = pat_frame(i)
          report "Frame " & to_string(i)
          & " did not come back off the link as it went out"
          severity failure;
        assert is_block(cfg_c, out_m_s) = (i = 0)
          report "Frame " & to_string(i) & " states a block where there is none"
          severity failure;
        assert is_last(cfg_c, out_m_s) = (i = block_frame_count_c-1)
          report "Frame " & to_string(i) & " closes a packet where it should not"
          severity failure;
        assert not is_error(cfg_c, out_m_s)
          report "Packet came back marked in error"
          severity failure;
      elsif is_last(cfg_c, out_m_s) then
        -- One bit of one subframe was flipped, which parity always
        -- catches.  The packet holding it has to say so.
        caught_s <= caught_s or is_error(cfg_c, out_m_s);
      end if;

      got_s <= got_s + 1;

      if i = block_frame_count_c-1 then
        i := 0;
        packets := packets + 1;
      else
        i := i + 1;
      end if;

      wait until rising_edge(clock_s) and is_taken(cfg_c, out_m_s, out_s_s);
      f := frame(cfg_c, out_m_s);
    end loop;
  end process;

  main: process is
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    -- Two whole blocks back, which takes the link a while
    while got_s < 2 * block_frame_count_c
    loop
      wait until rising_edge(clock_s);
    end loop;

    assert underflow_s = '0' and overflow_s = '0'
      report "The link lost a frame with nothing holding either end up"
      severity failure;

    -- Then break one bit and see the link say so.  A receiver that
    -- read parity the other way round would call every good packet bad
    -- and this one good, so passing both halves is what pins which way
    -- round it is.
    armed_s <= true;

    -- A packet is only marked as it closes, which is up to a block of
    -- frames away, and a frame is many cycles of this clock
    for i in 0 to 3 * block_frame_count_c * 64
    loop
      wait until rising_edge(clock_s);
      exit when caught_s;
    end loop;

    assert caught_s
      report "A subframe with a bit flipped came back with its parity holding"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
