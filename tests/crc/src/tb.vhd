library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_inet, nsl_spdif, nsl_usb, nsl_line_coding;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
begin

  ieee_802_3: process
    constant params_c : nsl_data.crc.crc_params_t := nsl_inet.ethernet.fcs_params_c;
    constant context: log_context := "IEEE-802.3";
    -- Packet dump from some documentation ?
    constant data : byte_string := from_hex( "20cf301acea16238e0c2bd3008060001"
                                            &"0800060400016238e0c2bd300a2a2a01"
                                            &"0000000000000a2a2a02000000000000"
                                            &"00000000000000000000000022b72660");
  begin
    assert_equal(context, "compare",
                 crc_spill(params_c, crc_update(params_c, crc_init(params_c), data(0 to 59))),
                 data(60 to 63),
                 failure);

    assert_equal(context, "check constant",
                 unsigned(crc_update(params_c, crc_init(params_c), data)),
                 unsigned(crc_check(params_c)),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  aesebu: process
    constant params_c : nsl_data.crc.crc_params_t := nsl_spdif.spdif.aesebu_crc_params_c;
    constant context: log_context := "AES/EBU";
    -- Constant bitstreams sniffed from Samsung TV on HDMI ARC
    constant data : byte_string := from_hex("060c00020000000000000000000000000000000000000086");
    constant data2 : byte_string := from_hex("060000020000000000000000000000000000000000000063");
    constant data3 : byte_string := from_hex("040000020000000000000000000000000000000000000016");
  begin

    assert_equal(context, "compare",
                 crc_spill(params_c, crc_update(params_c, crc_init(params_c), data(0 to data'right-1))),
                 data(data'right to data'right),
                 failure);

    assert_equal(context, "check constant",
                 unsigned(crc_update(params_c, crc_init(params_c), data)),
                 unsigned(crc_check(params_c)),
                 failure);

    assert_equal(context, "compare",
                 crc_spill(params_c, crc_update(params_c, crc_init(params_c), data2(0 to data2'right-1))),
                 data2(data2'right to data2'right),
                 failure);

    assert_equal(context, "check constant",
                 unsigned(crc_update(params_c, crc_init(params_c), data2)),
                 unsigned(crc_check(params_c)),
                 failure);

    assert_equal(context, "compare",
                 crc_spill(params_c, crc_update(params_c, crc_init(params_c), data3(0 to data3'right-1))),
                 data3(data3'right to data3'right),
                 failure);

    assert_equal(context, "check constant",
                 unsigned(crc_update(params_c, crc_init(params_c), data3)),
                 unsigned(crc_check(params_c)),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  -- USB Test vectors from https://www.usb.org/sites/default/files/crcdes.pdf
  usb_token: process
    constant params_c : nsl_data.crc.crc_params_t := nsl_usb.usb.token_crc_params_c;
    constant context: log_context := "USB Token";
  begin
    -- 0000100011110100
    assert_equal(context, "SOF 710",
                 true,
                 crc_is_valid(params_c, from_hex("102f")),
                 failure);

    -- <devad><ep><crc> (transmit from left to right)
    -- 1010100011110111
    -- = 15 ef (byte stream)
    assert_equal(context, "Setup addr 15 ep e",
                 true,
                 crc_is_valid(params_c, from_hex("15ef")),
                 failure);

    assert_equal(context, "Setup addr 15 ep e",
                 std_ulogic_vector'("11101"), -- Transmit from right to left
                 std_ulogic_vector(crc_spill_vector(params_c, crc_update(params_c, crc_init(params_c), "11100010101"))),
                 failure);

    -- <devad><ep><crc> (transmit from left to right)
    -- 0101110010111100
    -- = 3a 3d (byte stream)
    assert_equal(context, "Setup addr 3a ep a",
                 true,
                 crc_is_valid(params_c, from_hex("3a3d")),
                 failure);

    assert_equal(context, "Setup addr 3a ep a",
                 std_ulogic_vector'("00111"), -- Transmit from right to left
                 std_ulogic_vector(crc_spill_vector(params_c, crc_update(params_c, crc_init(params_c), "10100111010"))),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  usb_data: process
    constant params_c : nsl_data.crc.crc_params_t := nsl_usb.usb.data_crc_params_c;
    constant context: log_context := "USB Data";
  begin
    -- 00 01 02 03 1111011101011110 (CRC is txed left to right)
    -- = 00 01 02 03 ef 7a (byte stream)
    assert_equal(context, "00010203",
                 from_hex("ef7a"),
                 crc_spill(params_c,
                           crc_update(params_c, crc_init(params_c), from_hex("00010203"))),
                 failure);

    assert_equal(context, "00010203",
                 std_ulogic_vector'(x"7aef"), -- Transmit from right to left
                 std_ulogic_vector(crc_spill_vector(params_c,
                           crc_update(params_c, crc_init(params_c), from_hex("00010203")))),
                 failure);

    assert_equal(context, "00010203",
                 true,
                 crc_is_valid(params_c, from_hex("00010203ef7a")),
                 failure);

    -- 23 45 67 89 0111000000111000
    -- = 23 45 67 89 0e 1c
    assert_equal(context, "23456789",
                 from_hex("0e1c"),
                 crc_spill(params_c,
                           crc_update(params_c, crc_init(params_c), from_hex("23456789"))),
                 failure);

    assert_equal(context, "23456789",
                 true,
                 crc_is_valid(params_c, from_hex("234567890e1c")),
                 failure);

    log_info(context, "done");
    wait;
  end process;

  -- Synthetic test vectors  
  hdlc: process
    constant params_c : nsl_data.crc.crc_params_t := nsl_line_coding.hdlc.fcs_params_c;
    constant context: log_context := "HDLC";
  begin
    assert_equal(context, "Base",
                 from_hex("cbe5"),
                 crc_spill(params_c,
                           crc_update(params_c, crc_init(params_c), from_hex("deadbeef"))),
                 failure);

    log_info(context, "done");
    wait;
  end process;
  
end;
