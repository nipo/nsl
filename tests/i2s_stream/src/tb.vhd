library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2s, nsl_audio, nsl_amba, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Sends frames out over I2S from a stream and reads them back into
-- one.
--
-- I2S sends a channel at a time, so what the two wrappers either side
-- of it have to agree on is which word was which channel.  A stream
-- going in has to come out as the same stream, frame for frame, with
-- left still left.
entity tb is
end entity;

architecture arch of tb is

  constant sample_bits_c: natural := 24;
  -- Short packets, so several go by without the test running long
  constant frames_per_packet_c: natural := 8;

  constant cfg_c: config_t := nsl_i2s.stream.stream_config(
    sample_bits => sample_bits_c,
    frames_per_packet => frames_per_packet_c);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal tx_m_s: nsl_amba.axi4_stream.master_t;
  signal tx_s_s: nsl_amba.axi4_stream.slave_t;

  signal sck_s, ws_s, sd_s: std_ulogic;

  signal tx_ready_s, tx_channel_s: std_ulogic;
  signal tx_data_s: unsigned(sample_bits_c-1 downto 0);
  signal underflow_s: std_ulogic;

  signal rx_valid_s, rx_channel_s: std_ulogic;
  signal rx_data_s: unsigned(sample_bits_c-1 downto 0);

  signal out_m_s: nsl_amba.axi4_stream.master_t;
  signal out_s_s: nsl_amba.axi4_stream.slave_t;
  signal overflow_s: std_ulogic;

  signal sent_s, got_s: natural;

  -- The wire runs from reset and the stream has nothing to give it
  -- yet, so the first words it sends are whatever the transmitter held.
  -- Underflow then is the truth being told; underflow once frames are
  -- flowing is not.
  signal armed_s: boolean := false;
  signal underflow_after_s: std_ulogic;

  -- What a frame numbered n holds.  The channels differ, so one
  -- arriving as the other shows.
  function frame_of(n: natural) return frame_t
  is
    variable ret: frame_t := frame_zero_c;
  begin
    ret(0).sample := to_sample(to_unsigned(n mod 4096, sample_bits_c),
                               CODING_SIGNED);
    ret(1).sample := to_sample(to_unsigned((16#800# + n) mod 4096, sample_bits_c),
                               CODING_SIGNED);
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

  feeder: nsl_i2s.stream.i2s_stream_transmitter
    generic map(
      config_c => cfg_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => tx_m_s,
      in_o => tx_s_s,

      ready_i => tx_ready_s,
      channel_i => tx_channel_s,
      data_o => tx_data_s,

      underflow_o => underflow_s
      );

  wire_tx: nsl_i2s.transmitter.i2s_transmitter_master
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sck_div_m1_i => to_unsigned(7, 4),

      sck_o => sck_s,
      ws_o => ws_s,
      sd_o => sd_s,

      ready_o => tx_ready_s,
      channel_o => tx_channel_s,
      data_i => tx_data_s
      );

  wire_rx: nsl_i2s.receiver.i2s_receiver_slave
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sck_i => sck_s,
      ws_i => ws_s,
      sd_i => sd_s,

      valid_o => rx_valid_s,
      channel_o => rx_channel_s,
      data_o => rx_data_s
      );

  gatherer: nsl_i2s.stream.i2s_stream_receiver
    generic map(
      config_c => cfg_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      valid_i => rx_valid_s,
      channel_i => rx_channel_s,
      data_i => rx_data_s,

      out_o => out_m_s,
      out_i => out_s_s,

      overflow_o => overflow_s
      );

  out_s_s <= accept(cfg_c, true);

  -- Frames in, as fast as the wire takes them
  source: process is
    variable n: natural := 0;
  begin
    sent_s <= 0;
    tx_m_s <= transfer_defaults(cfg_c);

    wait until reset_n_s = '1';

    loop
      tx_m_s <= transfer(cfg_c, frame_of(n),
                         last => (n mod frames_per_packet_c) = frames_per_packet_c-1);

      loop
        wait until rising_edge(clock_s);
        exit when is_taken(cfg_c, tx_m_s, tx_s_s);
      end loop;

      n := n + 1;
      sent_s <= n;
    end loop;
  end process;

  watch: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if armed_s and underflow_s = '1' then
        underflow_after_s <= '1';
      end if;
    end if;

    if reset_n_s = '0' then
      underflow_after_s <= '0';
    end if;
  end process;

  -- And out again, which has to be the same stream
  sink: process is
    variable f: frame_t;
    variable n: natural;
    variable beats: natural := 0;
  begin
    got_s <= 0;

    -- Let the stream get ahead of the wire before holding it to
    -- anything, so what is checked is a link running rather than one
    -- starting
    while sent_s < 4
    loop
      wait until rising_edge(clock_s);
    end loop;

    wait until rising_edge(clock_s) and is_taken(cfg_c, out_m_s, out_s_s);
    f := frame(cfg_c, out_m_s);
    -- Where the count had got to when reading started
    n := to_integer(f(0).sample(11 downto 0));
    armed_s <= true;

    loop
      assert f(0).sample = frame_of(n)(0).sample
        report "Frame " & to_string(n) & " came back with "
        & to_hex_string(std_ulogic_vector(f(0).sample))
        & " on the left, not "
        & to_hex_string(std_ulogic_vector(frame_of(n)(0).sample))
        severity failure;
      assert f(1).sample = frame_of(n)(1).sample
        report "Frame " & to_string(n)
        & " came back with the wrong thing on the right: "
        & to_hex_string(std_ulogic_vector(f(1).sample))
        severity failure;

      assert overflow_s = '0'
        report "A frame was lost with nothing holding the stream up"
        severity failure;

      n := n + 1;
      got_s <= got_s + 1;

      wait until rising_edge(clock_s) and is_taken(cfg_c, out_m_s, out_s_s);
      f := frame(cfg_c, out_m_s);
    end loop;
  end process;

  main: process is
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    -- Long enough for several packets to have gone by
    while got_s < 4 * frames_per_packet_c
    loop
      wait until rising_edge(clock_s);
    end loop;

    assert underflow_after_s = '0'
      report "The wire asked for a word the stream did not have"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
