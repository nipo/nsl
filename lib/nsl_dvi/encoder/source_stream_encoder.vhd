library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_line_coding, work;
use work.encoder.all;

entity source_stream_encoder is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;

    period_i: in period_t;

    pixel_i : in nsl_data.bytestream.byte_string(0 to 2);
    hsync_i : in std_ulogic;
    vsync_i : in std_ulogic;
    di_hdr_i : in std_ulogic_vector(1 downto 0) := "00";
    di_data_i : in std_ulogic_vector(7 downto 0) := "00000000";

    tmds_o : out work.dvi.symbol_vector_t
    );
end entity;

architecture beh of source_stream_encoder is

  signal de_s, terc4_s: std_ulogic_vector(0 to 2);
  subtype control_t is std_ulogic_vector(3 downto 0);
  type control_vector is array(integer range <>) of control_t;
  signal control_s: control_vector(0 to 2);

begin

  gen: process(period_i, di_hdr_i, di_data_i, hsync_i, vsync_i) is
  begin
    de_s <= "---";
    terc4_s <= "---";
    control_s(0) <= "----";
    control_s(1) <= "----";
    control_s(2) <= "----";
    
    case period_i is
      when PERIOD_CONTROL =>
        de_s <= "000";
        terc4_s <= "000";
        control_s(0) <= "-0" & vsync_i & hsync_i;
        control_s(1) <= "-000";
        control_s(2) <= "-000";

      when PERIOD_DI_PRE =>
        de_s <= "000";
        terc4_s <= "000";
        control_s(0) <= "-0" & vsync_i & hsync_i;
        control_s(1) <= "-001";
        control_s(2) <= "-001";

      when PERIOD_DI_GUARD =>
        de_s <= "000";
        terc4_s <= "100";
        control_s(0) <= "11" & vsync_i & hsync_i;
        control_s(1) <= "-100";
        control_s(2) <= "-100";

      when PERIOD_DI_DATA =>
        de_s <= "000";
        terc4_s <= "111";
        control_s(0) <= di_hdr_i & vsync_i & hsync_i;
        control_s(1) <= di_data_i(3 downto 0);
        control_s(2) <= di_data_i(7 downto 4);

      when PERIOD_VIDEO_PRE =>
        de_s <= "000";
        terc4_s <= "000";
        control_s(0) <= "-0" & vsync_i & hsync_i;
        control_s(1) <= "-001";
        control_s(2) <= "-000";

      when PERIOD_VIDEO_GUARD =>
        de_s <= "000";
        terc4_s <= "000";
        control_s(0) <= "-101";
        control_s(1) <= "-100";
        control_s(2) <= "-101";

      when PERIOD_VIDEO_DATA =>
        de_s <= "111";
        terc4_s <= "000";
    end case;
  end process;

  channels: for i in 0 to 2
  generate
    encoder: nsl_line_coding.tmds.tmds_encoder
      port map(
        clock_i => pixel_clock_i,
        reset_n_i => reset_n_i,

        de_i => de_s(i),
        pixel_i => unsigned(pixel_i(i)),

        terc4_i => terc4_s(i),
        control_i => control_s(i),

        symbol_o => tmds_o(i)
        );
  end generate;

end architecture;
