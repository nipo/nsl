library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_dvi, nsl_time, work;
use nsl_data.text.all;
use nsl_dvi.terminal.all;
use nsl_time.calendar.all;
use work.func.all;

-- Composes the stack status as the text and colors of the label
-- screen described by screen_labels_c.
entity screen_text is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    link_up_i : in std_ulogic;
    dhcp_valid_i : in std_ulogic;
    sntp_valid_i : in std_ulogic;
    address_i : in unsigned(31 downto 0);
    ntp_server_i : in unsigned(31 downto 0);
    seconds_i : in unsigned(31 downto 0);

    text_o : out string(1 to screen_text_length_c);
    colors_o : out label_color_vector(0 to screen_color_count_c-1)
    );
end entity;

architecture beh of screen_text is

  -- Indices in the palette of the top level
  constant color_black_c : label_color_t := x"00";
  constant color_red_c : label_color_t := x"01";
  constant color_green_c : label_color_t := x"02";
  constant color_yellow_c : label_color_t := x"04";
  constant color_cyan_c : label_color_t := x"05";
  constant color_white_c : label_color_t := x"07";

  function dotted(address : unsigned(31 downto 0)) return string
  is
  begin
    return to_decimal_string(address(31 downto 24), 3) & "."
      & to_decimal_string(address(23 downto 16), 3) & "."
      & to_decimal_string(address(15 downto 8), 3) & "."
      & to_decimal_string(address(7 downto 0), 3) & " ";
  end function;

  signal date_time_s : date_time_t;

begin

  -- seconds_i counts from the Unix epoch
  calendar: calendar_from_seconds
    generic map(
      epoch_year_c => 1970
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      seconds_i => seconds_i,
      date_time_o => date_time_s
      );

  text_o <= "NSL SNTP CLOCK  "
            & "LINK " & if_else(link_up_i = '1', "up", "- ")
            & "  DHCP " & if_else(dhcp_valid_i = '1', "ok", "- ")
            & "IP ADDRESS      "
            & dotted(address_i)
            & "NTP SERVER      "
            & dotted(ntp_server_i)
            & to_decimal_string(date_time_s.year, 4) & "-"
            & to_decimal_string(date_time_s.month, 2) & "-"
            & to_decimal_string(date_time_s.day, 2) & "   UTC"
            & to_decimal_string(date_time_s.hour, 2) & ":"
            & to_decimal_string(date_time_s.minute, 2) & ":"
            & to_decimal_string(date_time_s.second, 2)
            & " SNTP " & if_else(sntp_valid_i = '1', "ok", "- ");

  colors_o(screen_color_background_c) <= color_black_c;
  colors_o(screen_color_title_c) <= color_white_c;
  colors_o(screen_color_value_c) <= color_cyan_c;
  colors_o(screen_color_link_c) <= color_green_c when link_up_i = '1' and dhcp_valid_i = '1'
                                   else color_yellow_c when link_up_i = '1'
                                   else color_red_c;
  colors_o(screen_color_sntp_c) <= color_green_c when sntp_valid_i = '1' else color_red_c;

end architecture;
