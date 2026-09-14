library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_hdmi, nsl_video, nsl_color, nsl_data, nsl_line_coding,
  nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_dvi.dvi.all;
use nsl_hdmi.hdmi.all;

-- Sends colour bars and data islands out as an HDMI signal and reads
-- them back through sink_stream_decoder.
--
-- An HDMI link announces its data periods, so this checks what the
-- DVI loopback cannot: that a preamble and a guard band are seen for
-- what they are, that a guard band is exactly two symbols wide, and
-- that the 32 TERC4 symbols of an island come back as the bytes that
-- went in.
--
-- The packets themselves go round the same loop.  Several kinds are
-- sent in turn, so headers differ from one packet to the next and a
-- receiver that lost count would say so.  Every one has to come back
-- whole, in the order it was sent, with its parity holding.
entity tb is
end entity;

architecture arch of tb is

  -- Horizontal blanking has to hold a whole island with its preamble
  -- and guard bands, plus the video preamble that follows it.  This
  -- much holds several packets in one island, so the path a source
  -- takes when it puts them back to back is walked too.
  constant mode_c: mode_t := mode_build(16, 200, 8, 8,
                                        4, 5, 1, 2,
                                        60.0, '1', '1');
  constant geometry_c: geometry_t := geometry(mode_c);
  constant config_c: config_t := config(pixels => 1);
  constant bar_width_c: natural := 4;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pixels_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s, tmds_rx_s: nsl_dvi.dvi.symbol_vector_t;

  -- Breaks what an island says about itself, by putting a plain
  -- control word where the preamble states which period is coming.
  -- A sink that missed the announcement must lose the island, not
  -- read its guard band as the start of a picture.
  signal pre_break_s: boolean := false;
  signal breaking_s: boolean;

  signal di_s: nsl_hdmi.hdmi.data_island_t;
  signal di_valid_s, di_ready_s: std_ulogic;

  signal period_s: nsl_dvi.dvi.period_t;
  signal decoded_s: byte_string(0 to 2);
  signal hsync_s, vsync_s: std_ulogic;
  signal di_hdr_s: std_ulogic_vector(1 downto 0);
  signal di_data_s: std_ulogic_vector(7 downto 0);

  -- One bit of one symbol, flipped on request.  A BCH code of this
  -- distance always catches a single bit, so what this asks is
  -- whether the parity is being held against anything at all.
  signal corrupt_s: std_ulogic;
  signal corrupt_mask_s: std_ulogic_vector(7 downto 0);
  signal rx_data_s: std_ulogic_vector(7 downto 0);
  signal armed_s, caught_s: boolean := false;

  signal rx_valid_s, rx_error_s: std_ulogic;
  signal rx_packet_s: nsl_hdmi.hdmi.data_island_t;
  signal received_s: natural;

  type di_vector_t is array(natural range <>) of nsl_hdmi.hdmi.data_island_t;

  -- Sent round and round.  They differ in type, in length and in what
  -- their payload looks like -- all zeros and all ones both go
  -- through, which is what a parity that was quietly not computed
  -- would survive.
  constant island_list_c: di_vector_t(0 to 3) := (
    nsl_hdmi.hdmi.di_source_product_desc("NSL", "Decoder test"),
    nsl_hdmi.hdmi.di_avi_rgb,
    nsl_hdmi.hdmi.di_infoframe(nsl_hdmi.hdmi.infoframe_vendor_specific, 1,
                               byte_string'(0 to 26 => x"ff")),
    nsl_hdmi.hdmi.di_null);

  -- What the encoder sends out of a data island, in order: the header
  -- goes out a bit at a time on channel 0 and the subpackets go out
  -- two bits at a time on the other two, so what a symbol carries is
  -- not one byte of the packet.  Checking the stream against a
  -- recording of what was handed in would only restate the encoder,
  -- so this keeps to what a receiver can tell on its own.
  function bar_color(x: natural) return nsl_color.rgb.rgb24
  is
    constant index: natural := (x / bar_width_c) mod 8;
  begin
    return to_rgb24(rgb3_from_suv(std_ulogic_vector(to_unsigned(index, 3))));
  end function;

  function as_rgb24(channels: byte_string) return nsl_color.rgb.rgb24
  is
  begin
    return nsl_color.rgb.rgb24'(r => unsigned(channels(2)),
                                g => unsigned(channels(1)),
                                b => unsigned(channels(0)));
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

  bars: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => config_c,
      bar_width_c => bar_width_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      out_o => pixels_s.m,
      out_i => pixels_s.s
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

      tmds_i => tmds_rx_s,

      period_o => period_s,
      pixel_o => decoded_s,
      hsync_o => hsync_s,
      vsync_o => vsync_s,

      di_hdr_o => di_hdr_s,
      di_data_o => di_data_s
      );

  receiver: nsl_hdmi.decoder.data_island_receiver
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      period_i => period_s,
      di_hdr_i => di_hdr_s,
      di_data_i => rx_data_s,

      valid_o => rx_valid_s,
      packet_o => rx_packet_s,
      error_o => rx_error_s
      );

  breaking_s <= pre_break_s and period_s = PERIOD_DI_PRE;

  tmds_rx_s(0) <= tmds_s(0);
  tmds_rx_s(1) <= nsl_line_coding.tmds.control_encode("000")
                  when breaking_s else tmds_s(1);
  tmds_rx_s(2) <= nsl_line_coding.tmds.control_encode("000")
                  when breaking_s else tmds_s(2);

  corrupt_mask_s <= "00000001" when corrupt_s = '1' else "00000000";
  rx_data_s <= di_data_s xor corrupt_mask_s;

  -- Flips one bit of the first island symbol to go by once asked
  corrupter: process is
  begin
    corrupt_s <= '0';

    wait until armed_s;
    wait until rising_edge(clock_s) and period_s = PERIOD_DI_DATA;
    corrupt_s <= '1';
    wait until rising_edge(clock_s);
    corrupt_s <= '0';

    wait;
  end process;

  -- Keep handing the encoder islands to send, so blanking holds them
  -- as often as it can, and step through the list on every one taken
  islands: process is
    variable index: natural := 0;
  begin
    di_valid_s <= '0';
    di_s <= nsl_hdmi.hdmi.di_null;

    wait until reset_n_s = '1';

    di_valid_s <= '1';

    loop
      di_s <= island_list_c(index);
      wait until rising_edge(clock_s) and di_ready_s = '1';
      index := (index + 1) mod island_list_c'length;
    end loop;
  end process;

  -- What comes back, against what went in.  Where in the list the
  -- first packet sat is worked out rather than assumed: the encoder
  -- may have been part way through one when checking started.
  packet_check: process is
    variable got: nsl_hdmi.hdmi.data_island_t;
    variable err: std_ulogic;
    variable count, offset: natural;
    variable found: boolean;
  begin
    received_s <= 0;
    caught_s <= false;
    count := 0;
    offset := 0;

    wait until rising_edge(clock_s) and rx_valid_s = '1';
    got := rx_packet_s;
    err := rx_error_s;

    found := false;
    for i in island_list_c'range
    loop
      if got = island_list_c(i) then
        offset := i;
        found := true;
      end if;
    end loop;
    assert found
      report "The first packet off the link is none of the ones sent"
      severity failure;

    -- Content, for as long as the link is left alone
    while not armed_s
    loop
      assert err = '0'
        report "Parity failed on packet " & to_string(count)
        & ", type " & to_hex_string(got.packet_type)
        severity failure;
      assert got = island_list_c((offset + count) mod island_list_c'length)
        report "Packet " & to_string(count) & " came back as type "
        & to_hex_string(got.packet_type) & ", not the one that was sent"
        severity failure;

      count := count + 1;
      received_s <= count;

      wait until rising_edge(clock_s) and rx_valid_s = '1';
      got := rx_packet_s;
      err := rx_error_s;
    end loop;

    -- A bit has been flipped in the island going by, so the packet
    -- holding it has to come out marked.  The one in hand may already
    -- be it, and a couple more are allowed past while the island the
    -- flip landed in finishes -- but only a couple.
    for i in 0 to 3
    loop
      exit when err = '1';
      assert i /= 3
        report "A flipped bit went through with its parity holding"
        severity failure;

      wait until rising_edge(clock_s) and rx_valid_s = '1';
      err := rx_error_s;
    end loop;

    caught_s <= true;
    wait;
  end process;

  main: process is
    variable c: nsl_color.rgb.rgb24;
    variable guard_run, data_run, pre_run: natural;
    variable islands_seen, guards_seen: natural;
    variable packets, hdr_firsts: natural;
    variable video_syms, island_syms, pre_syms: natural;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s) and synced_s = '1';

    -- Land on a frame boundary, then walk two whole frames
    wait until rising_edge(clock_s) and vsync_s = '1';
    wait until rising_edge(clock_s) and vsync_s = '0';

    islands_seen := 0;
    guards_seen := 0;
    packets := 0;
    hdr_firsts := 0;

    for y in 0 to geometry_c.height-1
    loop
      -- Blanking, where the islands and the announcements live
      pre_run := 0;
      while period_s /= PERIOD_VIDEO_PRE
      loop
        case period_s is
          when PERIOD_DI_PRE =>
            null;

          when PERIOD_DI_GUARD =>
            -- A guard band is two symbols, no more and no less
            guard_run := 0;
            while period_s = PERIOD_DI_GUARD
            loop
              guard_run := guard_run + 1;
              wait until rising_edge(clock_s);
            end loop;
            assert guard_run = 2
              report "Data island guard band is " & to_string(guard_run)
              & " symbols wide" severity failure;
            guards_seen := guards_seen + 1;
            next;

          when PERIOD_DI_DATA =>
            data_run := 0;
            while period_s = PERIOD_DI_DATA
            loop
              -- An island states where it starts, and packet
              -- boundaries are counted from there
              if di_hdr_s(1) = '0' then
                hdr_firsts := hdr_firsts + 1;
                assert data_run = 0
                  report "An island states its start " & to_string(data_run)
                  & " symbols in" severity failure;
              end if;
              data_run := data_run + 1;
              wait until rising_edge(clock_s);
            end loop;
            assert data_run mod 32 = 0
              report "A data island holds " & to_string(data_run)
              & " symbols, which is not a whole number of packets"
              severity failure;
            islands_seen := islands_seen + 1;
            packets := packets + data_run / 32;
            next;

          when PERIOD_CONTROL =>
            null;

          when others =>
            assert false
              report "Blanking holds a period it should not, before line "
              & to_string(y)
              severity failure;
        end case;

        wait until rising_edge(clock_s);
      end loop;

      -- Video announcement, then its guard band, then the pixels
      while period_s = PERIOD_VIDEO_PRE
      loop
        pre_run := pre_run + 1;
        wait until rising_edge(clock_s);
      end loop;
      assert pre_run >= 8
        report "Video preamble is " & to_string(pre_run) & " symbols wide"
        severity failure;

      guard_run := 0;
      while period_s = PERIOD_VIDEO_GUARD
      loop
        guard_run := guard_run + 1;
        wait until rising_edge(clock_s);
      end loop;
      assert guard_run = 2
        report "Video guard band is " & to_string(guard_run) & " symbols wide"
        severity failure;

      for x in 0 to geometry_c.width-1
      loop
        assert period_s = PERIOD_VIDEO_DATA
          report "Pixel " & to_string(x) & "," & to_string(y)
          & " is not in a video period"
          severity failure;

        c := as_rgb24(decoded_s);
        assert c = bar_color(x)
          report "Pixel " & to_string(x) & "," & to_string(y)
          & " came off the wire as "
          & to_hex_string(std_ulogic_vector(c.r))
          & to_hex_string(std_ulogic_vector(c.g))
          & to_hex_string(std_ulogic_vector(c.b))
          severity failure;

        wait until rising_edge(clock_s);
      end loop;

      assert period_s = PERIOD_CONTROL
        report "Line " & to_string(y) & " runs past the pixels it holds"
        severity failure;
    end loop;

    -- The encoder was never short of islands to send, so blanking
    -- carried some
    assert islands_seen /= 0
      report "No data island came through"
      severity failure;

    -- A guard band on either side of every island
    assert guards_seen = 2 * islands_seen
      report to_string(islands_seen) & " islands came with "
      & to_string(guards_seen) & " guard bands"
      severity failure;

    -- Every island stated its start exactly once, which is what
    -- packet boundaries inside it are counted from
    assert hdr_firsts = islands_seen
      report to_string(islands_seen) & " islands came through stating "
      & to_string(hdr_firsts) & " starts"
      severity failure;

    -- Islands held more than one packet each, so packets back to back
    -- went through as well
    assert packets > islands_seen
      report "No island held packets back to back"
      severity failure;

    -- Every packet the symbols carried came back out whole.  The
    -- checker started at the first packet the link ever carried and
    -- the walk above at a frame boundary, so it has seen at least as
    -- many.
    assert received_s >= packets
      report to_string(packets) & " packets went by and only "
      & to_string(received_s) & " came back whole"
      severity failure;

    -- And parity says so when a bit does not survive the trip
    armed_s <= true;
    wait until caught_s;

    -- Now break what the islands say about themselves.  The
    -- announcement is what a sink follows an island by, and a TERC4
    -- word reads as data rather than as control, so a sink that lost
    -- it could take the guard band for the start of a picture and
    -- hold that for the whole island.  Nothing but the pixels of the
    -- frame may come out as video.
    pre_break_s <= true;

    wait until rising_edge(clock_s) and vsync_s = '1';
    wait until rising_edge(clock_s) and vsync_s = '0';
    wait until rising_edge(clock_s) and vsync_s = '1';
    wait until rising_edge(clock_s) and vsync_s = '0';

    video_syms := 0;
    island_syms := 0;
    pre_syms := 0;
    loop
      wait until rising_edge(clock_s);
      if period_s = PERIOD_VIDEO_DATA then
        video_syms := video_syms + 1;
      end if;
      if period_s = PERIOD_DI_DATA then
        island_syms := island_syms + 1;
      end if;
      if period_s = PERIOD_DI_PRE then
        pre_syms := pre_syms + 1;
      end if;
      exit when vsync_s = '1';
    end loop;

    assert video_syms = geometry_c.width * geometry_c.height
      report "A frame whose islands went unannounced carried "
      & to_string(video_syms) & " symbols of video, not "
      & to_string(geometry_c.width * geometry_c.height)
      & " (island " & to_string(island_syms) & ", preamble "
      & to_string(pre_syms) & ")"
      severity failure;

    done_s <= "1";
    wait;
  end process;

end architecture;
