library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_hdmi, nsl_video, nsl_color, nsl_spdif, nsl_data,
  nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;
use nsl_hdmi.hdmi.all;
use nsl_hdmi.audio.all;

-- Sends audio out over HDMI and reads it back.
--
-- The whole way round: samples go into the packet builder, out as
-- TERC4 symbols inside data islands, back through the DVI decoder and
-- the packet receiver, and out of the audio receiver as samples again.
-- What went in has to come out, in order, on the right channel.
--
-- The packets are built by the sending half of this library rather
-- than by hand here, so what is checked is that the two halves agree
-- on where a sample sits in a subpacket -- which is not a thing a
-- receiver can work out on its own.
--
-- A source states its audio rate as N and CTS rather than as a rate,
-- so those make the trip too, and the clock they describe is counted
-- to see whether it comes out at the rate they meant.
entity tb is
end entity;

architecture arch of tb is

  -- Blanking wide enough to hold islands, as an audio link needs it to
  constant mode_c: mode_t := mode_build(16, 200, 8, 8,
                                        4, 5, 1, 2,
                                        60.0, '1', '1');
  constant geometry_c: geometry_t := geometry(mode_c);
  constant config_c: config_t := config(pixels => 1);

  -- N as the packet builder states it, and a CTS making the audio
  -- clock a tenth of the link clock so the ticks can simply be counted
  constant n_c: natural := 4096;
  constant cts_c: natural := n_c * 10;
  constant mclk_divisor_c: natural := cts_c / n_c;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pixels_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s: nsl_dvi.dvi.symbol_vector_t;

  signal di_s: nsl_hdmi.hdmi.data_island_t;
  signal di_valid_s, di_ready_s: std_ulogic;

  signal period_s: nsl_dvi.dvi.period_t;
  signal hsync_s, vsync_s: std_ulogic;
  signal di_hdr_s: std_ulogic_vector(1 downto 0);
  signal di_data_s: std_ulogic_vector(7 downto 0);

  signal rx_valid_s, rx_error_s: std_ulogic;
  signal rx_packet_s: nsl_hdmi.hdmi.data_island_t;

  -- What goes in: a counter, so what comes out says whether any was
  -- lost or reordered.  The channels carry different things, so one
  -- arriving as the other would show.
  signal pcm_index_s: unsigned(19 downto 0);
  signal pcm_a_s, pcm_b_s: nsl_spdif.blocker.channel_data_t;
  signal pcm_ready_s: std_ulogic;

  signal cts_send_s: std_ulogic;
  signal cts_gap_s: unsigned(11 downto 0);

  signal audio_valid_s, audio_block_s, audio_flat_s: std_ulogic;
  signal audio_a_s, audio_b_s: channel_sample_t;
  signal acr_valid_s: std_ulogic;
  signal acr_cts_s, acr_n_s: unsigned(19 downto 0);

  signal clock_ready_s, mclk_s, sample_tick_s: std_ulogic;

  signal received_s: natural;
  signal acr_seen_s: natural;
  signal counting_s: boolean := false;

  constant aux_a_c: unsigned(3 downto 0) := "0101";
  constant aux_b_c: unsigned(3 downto 0) := "1010";

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

  bars: nsl_dvi.pattern.color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => config_c,
      bar_width_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      out_o => pixels_s.m,
      out_i => pixels_s.s
      );

  -- What goes in, advancing only as the packet builder takes it
  pcm: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if pcm_ready_s = '1' then
        pcm_index_s <= pcm_index_s + 1;
      end if;

      cts_gap_s <= cts_gap_s + 1;
    end if;

    if reset_n_s = '0' then
      pcm_index_s <= (others => '0');
      cts_gap_s <= (others => '0');
    end if;
  end process;

  pcm_a_s.audio <= pcm_index_s;
  pcm_a_s.aux <= aux_a_c;
  pcm_a_s.valid <= '1';
  pcm_b_s.audio <= not pcm_index_s;
  pcm_b_s.aux <= aux_b_c;
  pcm_b_s.valid <= '1';

  -- A source restates the rate every so often
  cts_send_s <= '1' when cts_gap_s = 0 else '0';

  builder: nsl_hdmi.audio.hdmi_spdif_di_encoder
    generic map(
      audio_clock_divisor_c => n_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      cts_send_i => cts_send_s,
      cts_i => to_unsigned(cts_c, 20),

      block_valid_i => '1',
      block_user_i => (others => '0'),
      block_channel_status_i => (others => '0'),

      ready_o => pcm_ready_s,
      valid_i => '1',
      a_i => pcm_a_s,
      b_i => pcm_b_s,

      di_valid_o => di_valid_s,
      di_ready_i => di_ready_s,
      di_o => di_s
      );

  encoder: nsl_hdmi.encoder.hdmi_13_encoder
    generic map(
      config_c => config_c
      )
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      v_fp_m1_i => v_fp_m1(mode_c),
      v_sync_m1_i => v_sync_m1(mode_c),
      v_bp_m1_i => v_bp_m1(mode_c),
      v_act_m1_i => v_act_m1(mode_c),

      h_fp_m1_i => h_fp_m1(mode_c),
      h_sync_m1_i => h_sync_m1(mode_c),
      h_bp_m1_i => h_bp_m1(mode_c),
      h_act_m1_i => h_act_m1(mode_c),

      vsync_i => mode_c.v.sync,
      hsync_i => mode_c.h.sync,

      pixel_i => pixels_s.m,
      pixel_o => pixels_s.s,
      synced_o => synced_s,

      di_valid_i => di_valid_s,
      di_ready_o => di_ready_s,
      di_i => di_s,

      tmds_o => tmds_s
      );

  decoder: nsl_dvi.decoder.sink_stream_decoder
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      tmds_i => tmds_s,

      period_o => period_s,
      pixel_o => open,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => di_hdr_s,
      di_data_o => di_data_s
      );

  packets: nsl_hdmi.decoder.data_island_receiver
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      period_i => period_s,
      di_hdr_i => di_hdr_s,
      di_data_i => di_data_s,

      valid_o => rx_valid_s,
      packet_o => rx_packet_s,
      error_o => rx_error_s
      );

  audio: nsl_hdmi.audio.hdmi_audio_receiver
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      valid_i => rx_valid_s,
      error_i => rx_error_s,
      packet_i => rx_packet_s,

      acr_valid_o => acr_valid_s,
      cts_o => acr_cts_s,
      n_o => acr_n_s,

      valid_o => audio_valid_s,
      a_o => audio_a_s,
      b_o => audio_b_s,
      block_start_o => audio_block_s,
      flat_o => audio_flat_s
      );

  recovery: nsl_hdmi.audio.hdmi_audio_clock_recovery
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      valid_i => acr_valid_s,
      cts_i => acr_cts_s,
      n_i => acr_n_s,

      ready_o => clock_ready_s,
      mclk_tick_o => mclk_s,
      sample_tick_o => sample_tick_s
      );

  -- What a source said about the rate has to arrive as it was said
  acr_check: process is
    variable count: natural := 0;
  begin
    acr_seen_s <= 0;

    loop
      wait until rising_edge(clock_s) and acr_valid_s = '1';

      assert acr_cts_s = to_unsigned(cts_c, 20)
        report "CTS came back as " & to_string(to_integer(acr_cts_s))
        & ", not " & to_string(cts_c)
        severity failure;
      assert acr_n_s = to_unsigned(n_c, 20)
        report "N came back as " & to_string(to_integer(acr_n_s))
        & ", not " & to_string(n_c)
        severity failure;

      count := count + 1;
      acr_seen_s <= count;
    end loop;
  end process;

  -- What went in has to come out, in order, on the right channel
  sample_check: process is
    variable index: unsigned(19 downto 0);
    variable count: natural := 0;
  begin
    received_s <= 0;

    wait until rising_edge(clock_s) and audio_valid_s = '1';
    -- Where the counter had got to when checking started
    index := audio_a_s.data(23 downto 4);

    loop
      assert audio_a_s.data = unsigned'(index & aux_a_c)
        report "Sample " & to_string(count) & " channel A came back as "
        & to_hex_string(std_ulogic_vector(audio_a_s.data)) & ", not "
        & to_hex_string(std_ulogic_vector'(std_ulogic_vector(index) & std_ulogic_vector(aux_a_c)))
        severity failure;
      assert audio_b_s.data = unsigned'((not index) & aux_b_c)
        report "Sample " & to_string(count) & " channel B came back as "
        & to_hex_string(std_ulogic_vector(audio_b_s.data))
        & ", which is not the other channel's"
        severity failure;

      -- Linear PCM was sent, so neither channel may claim otherwise
      assert audio_a_s.v = '0' and audio_b_s.v = '0'
        report "Sample " & to_string(count) & " came back stated as not PCM"
        severity failure;
      assert audio_flat_s = '0'
        report "Sample " & to_string(count) & " came back stated as silence"
        severity failure;

      count := count + 1;
      received_s <= count;
      index := index + 1;

      wait until rising_edge(clock_s) and audio_valid_s = '1';
    end loop;
  end process;

  main: process is
    variable ticks, samples, cycles: natural;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s) and synced_s = '1';

    -- Let the link settle and the first rate statement through
    for i in 0 to 20000
    loop
      wait until rising_edge(clock_s);
    end loop;

    assert acr_seen_s /= 0
      report "No rate was ever stated"
      severity failure;
    assert clock_ready_s = '1'
      report "The audio clock never got a rate to run at"
      severity failure;

    -- The recovered clock, counted against the one it came from.  Its
    -- spacing wanders by a cycle, so what is held to account is the
    -- rate over a long enough run for that to wash out.
    ticks := 0;
    samples := 0;
    cycles := 100000;
    for i in 1 to cycles
    loop
      wait until rising_edge(clock_s);
      if mclk_s = '1' then
        ticks := ticks + 1;
      end if;
      if sample_tick_s = '1' then
        samples := samples + 1;
      end if;
    end loop;

    -- N over CTS of the link clock, within a tick either way
    assert ticks >= cycles / mclk_divisor_c - 1
      and ticks <= cycles / mclk_divisor_c + 1
      report to_string(ticks) & " audio clock ticks in " & to_string(cycles)
      & " link cycles, not " & to_string(cycles / mclk_divisor_c)
      severity failure;

    -- And one sample tick to every 128 of those
    assert samples >= ticks / 128 - 1 and samples <= ticks / 128 + 1
      report to_string(samples) & " sample ticks to " & to_string(ticks)
      & " audio clock ticks, which is not one in 128"
      severity failure;

    assert received_s > 100
      report "Only " & to_string(received_s) & " samples made the trip"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
