library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.edid.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_data.binary_io.all;

-- Builds EDID blocks and reads them back the way a source would.
--
-- A source takes the block apart byte by byte, so what is checked
-- here is the bytes: the header it looks for, the checksum it holds
-- the block against, and the detailed timing it takes its mode from.
entity tb is
end entity;

architecture arch of tb is

  constant modes_c: mode_t := mode_std_1280x720p60_c;

begin

  main: process is
    file fd: binary_file;
    variable blk, multi: edid_block_t;
    variable full: byte_string(0 to 255);

    -- What a source pulls back out of a detailed timing.
    procedure check_timing(constant d: descriptor_t;
                           constant mode: mode_t;
                           constant msg: string) is
      variable v: natural;
    begin
      v := to_integer(d(1)) * 256 + to_integer(d(0));
      assert v = (pixel_clock_hz(mode) + 5000) / 10000
        report msg & ": pixel clock reads " & to_string(v) & " times ten kHz"
        severity failure;

      v := (to_integer(d(4)) / 16) * 256 + to_integer(d(2));
      assert v = mode.h.active
        report msg & ": horizontal active reads " & to_string(v)
        severity failure;

      v := (to_integer(d(4)) mod 16) * 256 + to_integer(d(3));
      assert v = mode.h.blank
        report msg & ": horizontal blanking reads " & to_string(v)
        severity failure;

      v := (to_integer(d(7)) / 16) * 256 + to_integer(d(5));
      assert v = mode.v.active
        report msg & ": vertical active reads " & to_string(v)
        severity failure;

      v := (to_integer(d(7)) mod 16) * 256 + to_integer(d(6));
      assert v = mode.v.blank
        report msg & ": vertical blanking reads " & to_string(v)
        severity failure;

      v := (to_integer(d(11)) / 64) * 256 + to_integer(d(8));
      assert v = mode.h.off
        report msg & ": horizontal front porch reads " & to_string(v)
        severity failure;

      v := ((to_integer(d(11)) / 16) mod 4) * 256 + to_integer(d(9));
      assert v = mode.h.width
        report msg & ": horizontal sync width reads " & to_string(v)
        severity failure;

      v := ((to_integer(d(11)) / 4) mod 4) * 16 + to_integer(d(10)) / 16;
      assert v = mode.v.off
        report msg & ": vertical front porch reads " & to_string(v)
        severity failure;

      v := (to_integer(d(11)) mod 4) * 16 + to_integer(d(10)) mod 16;
      assert v = mode.v.width
        report msg & ": vertical sync width reads " & to_string(v)
        severity failure;

      -- Digital separate sync, and the polarities the mode states
      assert (to_integer(d(17)) / 8) mod 4 = 3
        report msg & ": sync is not stated as digital separate"
        severity failure;
      assert ((to_integer(d(17)) / 4) mod 2 = 1) = (mode.v.sync = '1')
        report msg & ": vertical sync polarity does not match"
        severity failure;
      assert ((to_integer(d(17)) / 2) mod 2 = 1) = (mode.h.sync = '1')
        report msg & ": horizontal sync polarity does not match"
        severity failure;
    end procedure;

    -- Every mode the library states has to survive the trip
    procedure check_mode(constant mode: mode_t; constant msg: string) is
      variable b: edid_block_t;
    begin
      b := edid_block(mode => mode,
                      manufacturer => "NSL",
                      product_code => 1,
                      name => "NSL Sink",
                      h_size_mm => 160,
                      v_size_mm => 90);

      assert checksum_of(b) = x"00"
        report msg & ": block does not sum to zero"
        severity failure;

      check_timing(b(54 to 71), mode, msg);
    end procedure;
  begin
    -- The header a source looks for to know it read anything at all

    blk := edid_block(mode => modes_c,
                      manufacturer => "NSL",
                      product_code => 16#1234#,
                      serial => 16#12345678#,
                      week => 5,
                      year => 2026,
                      name => "NSL Sink",
                      h_size_mm => 160,
                      v_size_mm => 90);

    assert blk(0) = x"00" and blk(7) = x"00"
      and blk(1 to 6) = byte_string'(x"ff", x"ff", x"ff", x"ff", x"ff", x"ff")
      report "Header is not the one a source looks for"
      severity failure;

    -- Manufacturer, three letters of five bits.  N is 14, S is 19,
    -- L is 12.
    assert blk(8 to 9) = byte_string'(x"3a", x"6c")
      report "Manufacturer reads " & to_hex_string(blk(8 to 9))
      severity failure;

    assert blk(10) = x"34" and blk(11) = x"12"
      report "Product code does not read back"
      severity failure;
    assert blk(12 to 15) = byte_string'(x"78", x"56", x"34", x"12")
      report "Serial does not read back"
      severity failure;
    assert blk(16) = to_byte(5) and blk(17) = to_byte(2026 - 1990)
      report "Date does not read back"
      severity failure;

    -- EDID 1.3, digital
    assert blk(18) = x"01" and blk(19) = x"03"
      report "Version is not 1.3"
      severity failure;
    assert to_integer(blk(20)) / 128 = 1
      report "Input is not stated as digital"
      severity failure;

    -- The first descriptor is the preferred timing, which is what
    -- bit 1 of the feature byte promises
    assert (to_integer(blk(24)) / 2) mod 2 = 1
      report "The first descriptor is not promised as preferred"
      severity failure;

    -- No extension, which is what asks for DVI rather than HDMI
    assert blk(126) = x"00"
      report "An extension block is advertised, which asks for HDMI"
      severity failure;

    assert checksum_of(blk) = x"00"
      report "Block does not sum to zero"
      severity failure;

    -- Descriptor slots are what they claim to be
    assert blk(72 to 74) = byte_string'(x"00", x"00", x"00")
      and blk(75) = x"fd"
      report "Second descriptor is not the range limits"
      severity failure;
    assert blk(90 to 92) = byte_string'(x"00", x"00", x"00")
      and blk(93) = x"fc"
      report "Third descriptor is not the monitor name"
      severity failure;
    assert blk(95 to 102) = to_byte_string("NSL Sink")
      report "Monitor name does not read back"
      severity failure;

    check_timing(blk(54 to 71), modes_c, "1280x720p60");

    -- Every mode the library states, through the same trip

    check_mode(mode_std_1920x1080p50_c, "1920x1080p50");
    check_mode(mode_std_1280x720p50_c, "1280x720p50");
    check_mode(mode_std_720x576p50_c, "720x576p50");
    check_mode(mode_std_1920x1080p60_c, "1920x1080p60");
    check_mode(mode_std_1920x1080p30_c, "1920x1080p30");
    check_mode(mode_std_1280x720p60_c, "1280x720p60");
    check_mode(mode_std_640x480p5994_c, "640x480p59.94");
    check_mode(mode_std_720x480p5994_c, "720x480p59.94");
    check_mode(mode_std_640x480p60_c, "640x480p60");
    check_mode(mode_std_800x600p60_c, "800x600p60");
    check_mode(mode_std_1024x768p60_c, "1024x768p60");
    check_mode(mode_std_1280x1024p60_c, "1280x1024p60");

    -- A sink offering several modes

    multi := edid_block(modes => mode_vector'(mode_std_640x480p60_c,
                                              mode_std_800x600p60_c,
                                              mode_std_1024x768p60_c),
                        manufacturer => "NSL",
                        product_code => 2,
                        name => "NSL Capture",
                        h_size_mm => 160,
                        v_size_mm => 120);

    assert checksum_of(multi) = x"00"
      report "Multi-mode block does not sum to zero"
      severity failure;

    -- The first mode is the preferred one and states its timings
    check_timing(multi(54 to 71), mode_std_640x480p60_c, "preferred");
    -- The second takes the slot left over
    check_timing(multi(108 to 125), mode_std_800x600p60_c, "second");

    -- What did not fit is advertised by resolution and rate alone.
    -- 1024 is 128 eight-pixel units, so 128-31 = 97, at 4:3 and 60 Hz.
    assert multi(38) = to_byte(97) and multi(39) = to_byte(64)
      report "Third mode does not read back as a standard timing"
      severity failure;
    assert multi(40 to 41) = unused_standard_timing
      report "A standard timing is stated that was not asked for"
      severity failure;

    -- Range limits cover every mode on offer.  640x480p60 runs its
    -- lines at 31.5 kHz and 1024x768p60 at 48.4 kHz.
    assert multi(75) = x"fd"
      report "Second descriptor is not the range limits"
      severity failure;
    assert to_integer(multi(77)) <= 60 and to_integer(multi(78)) >= 60
      report "Vertical range does not cover the modes on offer"
      severity failure;
    assert to_integer(multi(79)) <= 31 and to_integer(multi(80)) >= 49
      report "Horizontal range does not cover the modes on offer"
      severity failure;
    assert to_integer(multi(81)) * 10 >= 65
      report "Pixel clock limit is below the fastest mode on offer"
      severity failure;

    -- An HDMI sink, which is a base block plus a CTA extension.  What
    -- a source reads out of that extension is what makes it send data
    -- islands rather than plain DVI.

    full := edid_data(modes => mode_vector'(0 => mode_std_1280x720p60_c),
                      manufacturer => "NSL",
                      product_code => 3,
                      name => "NSL Capture",
                      h_size_mm => 160,
                      v_size_mm => 90,
                      hdmi => true,
                      audio_channels => 2);

    -- One block follows, and both sum to zero
    assert full(126) = to_byte(1)
      report "The base block does not state an extension"
      severity failure;
    assert checksum_of(full(0 to 127)) = x"00"
      report "Base block does not sum to zero once an extension is stated"
      severity failure;
    assert checksum_of(full(128 to 255)) = x"00"
      report "Extension block does not sum to zero"
      severity failure;

    -- A CTA extension, revision three
    assert full(128) = x"02" and full(129) = x"03"
      report "Extension is not a CTA revision three block"
      severity failure;

    -- Underscan and basic audio, no YCbCr
    assert to_integer(full(131)) / 128 = 1
      report "Underscan is not stated"
      severity failure;
    assert (to_integer(full(131)) / 64) mod 2 = 1
      report "Basic audio is not stated, so a source sends none"
      severity failure;
    assert (to_integer(full(131)) / 16) mod 4 = 0
      report "YCbCr is offered, which lets a source send something other than RGB"
      severity failure;

    -- The HDMI vendor block comes first, and is the whole handshake
    assert full(132) = x"67"
      report "First data block is not a vendor block of seven bytes"
      severity failure;
    assert full(133 to 135) = byte_string'(x"03", x"0c", x"00")
      report "Vendor block does not carry the HDMI OUI, so the link stays DVI"
      severity failure;
    assert full(136) = x"00" and full(137) = x"00"
      report "Physical address is not the root one"
      severity failure;
    -- 74.25 MHz, in units of five
    assert full(139) = to_byte(15)
      report "Maximum TMDS clock reads " & to_string(to_integer(full(139)) * 5) & " MHz"
      severity failure;

    -- Then the modes, by VIC.  720p60 is VIC 4, and the first mode on
    -- offer is marked native.
    assert full(140) = x"41"
      report "Second data block is not one video descriptor"
      severity failure;
    assert full(141) = to_byte(128 + 4)
      report "Mode does not read back as native VIC 4"
      severity failure;

    -- Then what audio may be sent: two channels of LPCM, the three
    -- rates every source has, all three depths
    assert full(142) = x"23"
      report "Third data block is not one audio descriptor"
      severity failure;
    assert full(143) = x"09"
      report "Audio descriptor is not two channels of LPCM"
      severity failure;
    assert full(144) = x"07" and full(145) = x"07"
      report "Audio rates or depths do not read back"
      severity failure;

    assert full(146) = x"83"
      report "Fourth data block is not a speaker allocation"
      severity failure;
    assert full(147) = x"01"
      report "Speaker allocation is not stereo"
      severity failure;

    -- Nothing follows the data blocks
    assert full(130) = to_byte(22)
      report "Descriptors are said to start at " & to_string(to_integer(full(130)))
      severity failure;

    -- A DVI sink is one block, and stating no audio is what it does
    assert edid_data(modes => mode_vector'(0 => mode_std_1280x720p60_c),
                     manufacturer => "NSL", product_code => 3)'length = 128
      report "A DVI sink hands more than one block"
      severity failure;

    assert cea_vic(mode_std_1920x1080p60_c) = 16
      and cea_vic(mode_std_640x480p60_c) = 1
      and cea_vic(mode_std_1920x1080p30_c) = 34
      report "A mode does not carry the VIC CEA gives it"
      severity failure;
    assert cea_vic(mode_std_1024x768p60_c) = 0
      report "A VESA mode is given a VIC, which CEA does not name"
      severity failure;

    -- Written out so it can be held against an independent reader.
    -- edid-decode takes it straight.
    file_open(fd, "edid.bin", WRITE_MODE);
    write(fd, blk);
    file_close(fd);

    file_open(fd, "edid-multi.bin", WRITE_MODE);
    write(fd, multi);
    file_close(fd);

    file_open(fd, "edid-hdmi.bin", WRITE_MODE);
    write(fd, full);
    file_close(fd);

    report "EDID written, 128 bytes" severity note;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
