library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_audio, nsl_amba, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_data.endian.all;

-- Puts frames on a stream and takes them off again.
--
-- What is checked is the things a reader cannot see for itself: where
-- a sample sits in TDATA, that a narrow signed sample comes back as
-- the number it was rather than the field it travelled in, and that
-- the framing bits land where the package says they do.
entity tb is
end entity;

architecture arch of tb is
begin

  main: process is

    -- One frame through a configuration and back
    procedure check_roundtrip(constant cfg: config_t;
                              constant f: frame_t;
                              constant msg: string) is
      variable m: master_t;
      variable got: frame_t;
    begin
      m := transfer(cfg, f, last => true, block_start => true);

      assert is_valid(cfg, m)
        report msg & ": beat is not valid"
        severity failure;
      assert is_last(cfg, m)
        report msg & ": beat does not close a packet"
        severity failure;
      assert is_block(cfg, m)
        report msg & ": beat does not open a block"
        severity failure;
      assert not is_error(cfg, m)
        report msg & ": beat is marked in error"
        severity failure;

      got := frame(cfg, m);

      for c in 0 to cfg.channel_count-1
      loop
        assert got(c).sample = f(c).sample
          report msg & ": channel " & to_string(c) & " came back as "
          & to_hex_string(std_ulogic_vector(got(c).sample)) & ", not "
          & to_hex_string(std_ulogic_vector(f(c).sample))
          severity failure;

        for b in 0 to cfg.sideband_bits-1
        loop
          assert got(c).sideband(b) = f(c).sideband(b)
            report msg & ": channel " & to_string(c) & " sideband bit "
            & to_string(b) & " did not come back"
            severity failure;
        end loop;
      end loop;

      -- Channels the stream does not carry read as nothing
      for c in cfg.channel_count to max_channel_count_c-1
      loop
        assert got(c).sample = sample_zero_c
          report msg & ": a channel the stream does not carry came back set"
          severity failure;
      end loop;
    end procedure;

    -- A frame whose channels differ, so one arriving as another shows.
    -- The value stays small enough to fit the narrowest stream here
    -- and positive enough not to turn into a sign under either coding.
    function counting_frame(constant cfg: config_t) return frame_t is
      variable ret: frame_t := frame_zero_c;
      variable v: unsigned(max_sample_bits_c-1 downto 0);
    begin
      for c in 0 to cfg.channel_count-1
      loop
        v := (others => '0');
        v(cfg.sample_bits-1 downto 0) := to_unsigned(
          (16#2a# + c * 7) mod 128, cfg.sample_bits);
        ret(c).sample := to_sample(v(cfg.sample_bits-1 downto 0), cfg.coding);

        for b in 0 to cfg.sideband_bits-1
        loop
          if ((c + b) mod 2) = 0 then
            ret(c).sideband(b) := '1';
          end if;
        end loop;
      end loop;

      return ret;
    end function;

    constant stereo24_c: config_t := config(channels => 2, sample_bits => 24,
                                            sideband_bits => 3);
    constant stereo16_c: config_t := config(channels => 2, sample_bits => 16);
    constant mono8_c: config_t := config(channels => 1, sample_bits => 8,
                                         coding => CODING_UNSIGNED);
    constant surround_c: config_t := config(channels => 8, sample_bits => 32,
                                            sideband_bits => 3);
    constant spdif20_c: config_t := config(channels => 2, sample_bits => 20,
                                           sideband_bits => 3);

    variable m: master_t;
    variable f: frame_t;
    variable got: frame_t;
    variable data_v: byte_string(0 to 63);
  begin
    -- What a configuration works out to

    assert sample_bytes(stereo24_c) = 3 and frame_bytes(stereo24_c) = 6
      report "A stereo 24 bit frame is not six bytes"
      severity failure;
    assert sample_bytes(spdif20_c) = 3
      report "A 20 bit sample is not held in three bytes"
      severity failure;
    assert sample_bytes(stereo16_c) = 2 and frame_bytes(stereo16_c) = 4
      report "A stereo 16 bit frame is not four bytes"
      severity failure;
    assert user_width(stereo24_c) = 2 + 2 * 3
      report "Framing bits and sideband do not add up"
      severity failure;
    assert user_width(stereo16_c) = 2
      report "A stream with no sideband states more than framing bits"
      severity failure;
    assert has_ready(stereo24_c)
      report "A stream that can hold beats back says it cannot"
      severity failure;

    -- Where a sample sits in TDATA: channel 0 first, least significant
    -- byte first within a channel.  This is the part a reader on the
    -- far end of a FIFO cannot work out.

    f := frame_zero_c;
    f(0).sample := to_sample(x"123456", CODING_SIGNED);
    f(1).sample := to_sample(x"abcdef", CODING_SIGNED);
    m := transfer(stereo24_c, f);

    data_v(0 to frame_bytes(stereo24_c)-1) := nsl_amba.axi4_stream.bytes(
      as_stream_config(stereo24_c), m, BYTE_ORDER_INCREASING);

    assert data_v(0 to 5) = byte_string'(x"56", x"34", x"12",
                                         x"ef", x"cd", x"ab")
      report "TDATA holds " & to_hex_string(data_v(0 to 5))
      & ", not channel 0 then channel 1, least significant byte first"
      severity failure;

    -- A narrow signed sample comes back as the number, not the field.
    -- Held in three bytes, twenty bits wide, and negative.

    f := frame_zero_c;
    f(0).sample := to_sample(to_unsigned(16#80000#, 20), CODING_SIGNED);
    f(1).sample := to_sample(to_unsigned(16#7ffff#, 20), CODING_SIGNED);
    m := transfer(spdif20_c, f);
    got := frame(spdif20_c, m);

    assert got(0).sample = to_sample(to_unsigned(16#80000#, 20), CODING_SIGNED)
      report "The most negative 20 bit sample came back as "
      & to_hex_string(std_ulogic_vector(got(0).sample))
      severity failure;
    assert signed(got(0).sample) < 0
      report "A negative sample came back positive"
      severity failure;
    assert signed(got(1).sample) > 0
      report "The most positive 20 bit sample came back negative"
      severity failure;

    -- And an unsigned one is not sign extended, so the same bits mean
    -- something else

    f := frame_zero_c;
    f(0).sample := to_sample(to_unsigned(16#80#, 8), CODING_UNSIGNED);
    m := transfer(mono8_c, f);
    got := frame(mono8_c, m);

    assert got(0).sample = to_unsigned(16#80#, max_sample_bits_c)
      report "An unsigned sample came back as "
      & to_hex_string(std_ulogic_vector(got(0).sample))
      severity failure;

    -- Every shape of stream carries a frame whole

    check_roundtrip(stereo24_c, counting_frame(stereo24_c), "stereo 24");
    check_roundtrip(stereo16_c, counting_frame(stereo16_c), "stereo 16");
    check_roundtrip(mono8_c, counting_frame(mono8_c), "mono 8");
    check_roundtrip(surround_c, counting_frame(surround_c), "8 channel 32");
    check_roundtrip(spdif20_c, counting_frame(spdif20_c), "stereo 20");

    -- Framing bits are separate things

    m := transfer(stereo24_c, frame_zero_c, last => true, error => true);
    assert is_last(stereo24_c, m) and is_error(stereo24_c, m)
      and not is_block(stereo24_c, m)
      report "A packet marked in error does not read back as one"
      severity failure;

    m := transfer(stereo24_c, frame_zero_c, valid => false);
    assert not is_valid(stereo24_c, m)
      report "A beat that was not offered reads as offered"
      severity failure;

    -- A block is what a packet holds, and channel status needs one
    assert stereo24_c.frames_per_packet = block_frame_count_c
      report "A packet does not hold a block of frames by default"
      severity failure;
    assert block_frame_count_c = 192
      report "A block of channel status is not 192 frames"
      severity failure;

    -- Rates are values beside a stream, not part of its shape
    assert rate_48k_c = to_rate(48_000) and rate_44k1_c /= rate_48k_c
      report "Rates do not read back"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
