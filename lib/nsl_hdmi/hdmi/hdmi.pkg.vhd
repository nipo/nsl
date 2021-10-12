library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_color;
use nsl_data.bytestream.all;

package hdmi is

  constant control_video_data_period_c : std_ulogic_vector(3 downto 0) := "0001";
  constant control_data_island_period_c : std_ulogic_vector(3 downto 0) := "0101";
  constant control_hdcp_en_c : std_ulogic_vector(3 downto 0) := "1001";

  type data_island_t is
  record
    packet_type: byte;
    hb: byte_string(1 to 2);
    pb: byte_string(0 to 27);
  end record;

  constant di_type_null              : byte    := x"00";
  constant di_type_audio_clock_regen : byte    := x"01";
  constant di_type_audio_sample      : byte    := x"02";
  constant di_type_general_control   : byte    := x"03";
  constant di_type_acp               : byte    := x"04";
  constant di_type_isrc1             : byte    := x"05";
  constant di_type_isrc2             : byte    := x"06";
  constant di_type_one_bit_audio     : byte    := x"07";
  constant di_type_dst_audio         : byte    := x"08";
  constant di_type_hbr_audio         : byte    := x"09";
  constant di_type_gamut             : byte    := x"0a";
  constant infoframe_vendor_specific : integer := 1;
  constant infoframe_avi             : integer := 2;
  constant infoframe_source_product  : integer := 3;
  constant infoframe_audio           : integer := 4;
  constant infoframe_mpeg_source     : integer := 5;
  
  function di_null return data_island_t;
  
  function di_infoframe(frame_type, version: integer;
                        data: byte_string) return data_island_t;

  function di_avi_rgb return data_island_t;

  function di_source_product_desc(vn, pd: string;
                                  source_info : integer := 0) return data_island_t;

  function di_audio_infoframe(cc, ct, ss, sf, cxt, ca, lfepbl0, lsv, dm: integer) return data_island_t;

  function rgb24_pack(color: nsl_color.rgb.rgb24) return byte_string;
  
end package hdmi;

package body hdmi is

  function di_infoframe(frame_type, version: integer;
                        data: byte_string) return data_island_t
  is
    variable ret : data_island_t;
    constant dl: natural := nsl_math.arith.min(data'length, 27);
    alias datax : byte_string(1 to data'length) is data;
    variable checksum: integer;
  begin
    ret.packet_type := to_byte(128 + frame_type);
    ret.hb(1) := to_byte(version);
    ret.hb(2) := to_byte(dl);
    ret.pb := (others => x"00");
    ret.pb(1 to 1+dl-1) := datax(1 to dl);

    checksum := to_integer(ret.packet_type);

    for i in ret.hb'range
    loop
      checksum := checksum + to_integer(ret.hb(i));
    end loop;

    for i in ret.pb'range
    loop
      checksum := checksum + to_integer(ret.pb(i));
    end loop;

    ret.pb(0) := to_byte((-checksum) mod 256);

    return ret;
  end function;

  function di_source_product_desc(vn, pd: string;
                                  source_info : integer := 0) return data_island_t
  is
    constant vl: natural := nsl_math.arith.min(vn'length, 8);
    constant pl: natural := nsl_math.arith.min(pd'length, 16);
    alias vnx : string(1 to vn'length) is vn;
    alias pdx : string(1 to pd'length) is pd;
    variable data: byte_string(0 to 24);
  begin
    data := (others => x"20");
    data(0 to vl-1) := to_byte_string(vnx(1 to vl));
    data(8 to pl+7) := to_byte_string(pdx(1 to pl));
    data(24) := to_byte(source_info);

    return di_infoframe(infoframe_source_product, 1, data);
  end function;

  function di_avi_rgb return data_island_t
  is
    variable data: byte_string(1 to 13);
  begin
    data := from_hex("02000000000000000000000000");
    return di_infoframe(infoframe_avi, 3, data);
  end function;

  function di_null return data_island_t
  is
    variable ret : data_island_t;
  begin
    ret.packet_type := x"00";
    ret.hb := (others => x"00");
    ret.pb := (others => x"00");
    return ret;
  end function;

  function di_audio_infoframe(cc, ct, ss, sf, cxt, ca, lfepbl0, lsv, dm: integer) return data_island_t
  is
    variable data: byte_string(1 to 10);
  begin
    data(1) := byte(to_unsigned(ct, 4) & "0" & to_unsigned(cc, 3));
    data(2) := byte("000" & to_unsigned(sf, 3) & to_unsigned(ss, 2));
    data(3) := byte("000" & to_unsigned(cxt, 5));
    data(4) := byte(to_unsigned(ca, 5));
    data(5) := byte(to_unsigned(dm, 1) & to_unsigned(lsv, 4) & "0" & to_unsigned(lfepbl0, 2));
    data(6 to 10) := (others => x"00");

    return di_infoframe(infoframe_audio, 1, data);
  end function;

  function rgb24_pack(color: nsl_color.rgb.rgb24) return byte_string
  is
    variable ret: byte_string(0 to 2);
  begin
    ret(0) := byte(color.b);
    ret(1) := byte(color.g);
    ret(2) := byte(color.r);
    return ret;
  end function;

end package body hdmi;
