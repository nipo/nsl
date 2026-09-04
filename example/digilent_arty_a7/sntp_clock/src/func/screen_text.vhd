library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_time;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_time.calendar.all;

-- Renders the stack status as a 16x8 text screen and streams it to
-- the terminal text buffer, one cell per cycle, forever.
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

    row_o : out unsigned(2 downto 0);
    column_o : out unsigned(3 downto 0);
    write_o : out std_ulogic;
    character_o : out unsigned(7 downto 0);
    foreground_o : out unsigned(2 downto 0)
    );
end entity;

architecture beh of screen_text is

  constant column_count_c : natural := 16;
  constant row_count_c : natural := 8;

  subtype line_t is byte_string(0 to column_count_c-1);
  type screen_t is array (0 to row_count_c-1) of line_t;

  subtype color_t is unsigned(2 downto 0);
  type color_vector is array (0 to row_count_c-1) of color_t;

  -- Indices in the palette of the top level
  constant color_red_c : color_t := "001";
  constant color_green_c : color_t := "010";
  constant color_yellow_c : color_t := "100";
  constant color_cyan_c : color_t := "101";
  constant color_white_c : color_t := "111";

  function dotted(address : unsigned(31 downto 0)) return line_t
  is
  begin
    return to_byte_string(to_decimal_string(address(31 downto 24), 3) & "."
                          & to_decimal_string(address(23 downto 16), 3) & "."
                          & to_decimal_string(address(15 downto 8), 3) & "."
                          & to_decimal_string(address(7 downto 0), 3) & " ");
  end function;

  type regs_t is
  record
    row : unsigned(2 downto 0);
    column : unsigned(3 downto 0);
  end record;

  signal r, rin : regs_t;

  signal date_time_s : date_time_t;
  signal screen_s : screen_t;
  signal colors_s : color_vector;

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

  screen_s(0) <= to_byte_string("NSL SNTP CLOCK  ");
  screen_s(1) <= to_byte_string("LINK " & if_else(link_up_i = '1', "up", "- ")
                                & "  DHCP " & if_else(dhcp_valid_i = '1', "ok", "- "));
  screen_s(2) <= to_byte_string("IP ADDRESS      ");
  screen_s(3) <= dotted(address_i);
  screen_s(4) <= to_byte_string("NTP SERVER      ");
  screen_s(5) <= dotted(ntp_server_i);
  screen_s(6) <= to_byte_string(to_decimal_string(date_time_s.year, 4) & "-"
                                & to_decimal_string(date_time_s.month, 2) & "-"
                                & to_decimal_string(date_time_s.day, 2) & "   UTC");
  screen_s(7) <= to_byte_string(to_decimal_string(date_time_s.hour, 2) & ":"
                                & to_decimal_string(date_time_s.minute, 2) & ":"
                                & to_decimal_string(date_time_s.second, 2)
                                & " SNTP " & if_else(sntp_valid_i = '1', "ok", "- "));

  colors_s(0) <= color_white_c;
  colors_s(1) <= color_green_c when link_up_i = '1' and dhcp_valid_i = '1'
                 else color_yellow_c when link_up_i = '1'
                 else color_red_c;
  colors_s(2) <= color_white_c;
  colors_s(3) <= color_cyan_c;
  colors_s(4) <= color_white_c;
  colors_s(5) <= color_cyan_c;
  colors_s(6) <= color_white_c;
  colors_s(7) <= color_green_c when sntp_valid_i = '1' else color_red_c;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.row <= (others => '0');
      r.column <= (others => '0');
    end if;
  end process;

  transition: process(r) is
  begin
    rin <= r;

    if r.column /= column_count_c - 1 then
      rin.column <= r.column + 1;
    else
      rin.column <= (others => '0');
      if r.row /= row_count_c - 1 then
        rin.row <= r.row + 1;
      else
        rin.row <= (others => '0');
      end if;
    end if;
  end process;

  output: process(r, screen_s, colors_s) is
  begin
    row_o <= r.row;
    column_o <= r.column;
    write_o <= '1';
    character_o <= unsigned(screen_s(to_integer(r.row))(to_integer(r.column)));
    foreground_o <= colors_s(to_integer(r.row));
  end process;

end architecture;
