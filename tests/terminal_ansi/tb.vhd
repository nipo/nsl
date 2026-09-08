library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_terminal, nsl_data, nsl_simulation;
use nsl_terminal.ansi.all;
use nsl_data.bytestream.all;

-- Feeds byte sequences to ansi_terminal and checks the resulting
-- screen against hand-computed expectations. The text buffer is
-- modeled by a spy process recording every write; cells are checked
-- in screen coordinates through the engine's row offset.
entity tb is
end entity;

architecture sim of tb is

  constant clock_period_c : time := 10 ns;

  constant row_count_c : natural := 10;
  constant column_count_c : natural := 20;
  constant row_count_l2_c : natural := 4;
  constant column_count_l2_c : natural := 5;
  constant buffer_rows_c : natural := 2 ** row_count_l2_c;
  constant buffer_columns_c : natural := 2 ** column_count_l2_c;

  constant esc_c : character := character'val(16#1b#);
  constant bel_c : character := character'val(16#07#);
  constant bs_c : character := character'val(16#08#);
  constant ht_c : character := character'val(16#09#);
  constant lf_c : character := character'val(16#0a#);
  constant cr_c : character := character'val(16#0d#);

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal valid_s, ready_s : std_ulogic;
  signal data_s : byte;

  signal row_offset_s : unsigned(row_count_l2_c-1 downto 0);
  signal row_s : unsigned(row_count_l2_c-1 downto 0);
  signal column_s : unsigned(column_count_l2_c-1 downto 0);
  signal enable_s, write_s, underline_s : std_ulogic;
  signal character_s : unsigned(7 downto 0);
  signal foreground_s, background_s : unsigned(3 downto 0);

  signal blink_s : std_ulogic := '0';
  signal rchar_s : unsigned(7 downto 0);
  signal rul_s : std_ulogic;
  signal rfg_s, rbg_s : unsigned(3 downto 0);

  signal reply_valid_s, reply_ready_s : std_ulogic;
  signal bell_s : std_ulogic;
  signal bell_count_s : natural := 0;
  signal local_echo_s : std_ulogic;
  signal reply_data_s : byte;
  signal reply_capture_s : string(1 to 32);
  signal reply_len_s : natural := 0;
  signal reply_clear_s : std_ulogic := '0';

  type cell_t is
  record
    char : unsigned(7 downto 0);
    fg, bg : unsigned(3 downto 0);
    ul : std_ulogic;
  end record;
  type cell_array_t is array(0 to buffer_rows_c * buffer_columns_c - 1) of cell_t;

  signal screen_s : cell_array_t;
  signal rd_s1_s : cell_t;

  signal done_s : boolean := false;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 4 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: ansi_terminal
    generic map(
      row_count_c => row_count_c,
      column_count_c => column_count_c,
      row_count_l2_c => row_count_l2_c,
      column_count_l2_c => column_count_l2_c,
      read_latency_c => 2
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => valid_s,
      ready_o => ready_s,
      data_i => data_s,

      cursor_blink_i => blink_s,

      reply_valid_o => reply_valid_s,
      reply_ready_i => reply_ready_s,
      reply_data_o => reply_data_s,

      bell_o => bell_s,
      local_echo_o => local_echo_s,

      row_offset_o => row_offset_s,

      row_o => row_s,
      column_o => column_s,
      enable_o => enable_s,
      write_o => write_s,
      character_o => character_s,
      underline_o => underline_s,
      foreground_o => foreground_s,
      background_o => background_s,
      character_i => rchar_s,
      underline_i => rul_s,
      foreground_i => rfg_s,
      background_i => rbg_s
      );

  -- Accepts the reply stream and accumulates it into a string, reset
  -- to empty when reply_len_s is set to 0 by the driver.
  reply_ready_s <= '1';
  reply_sink: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if reply_clear_s = '1' then
        reply_capture_s <= (others => ' ');
        reply_len_s <= 0;
      elsif reply_valid_s = '1' and reply_ready_s = '1' then
        reply_capture_s(reply_len_s + 1)
          <= character'val(to_integer(unsigned(reply_data_s)));
        reply_len_s <= reply_len_s + 1;
      end if;
    end if;
  end process;

  -- Serves engine reads with the buffer's two-cycle registered-output
  -- latency: a stage-1 register captures the addressed cell, the read
  -- outputs take it the next enabled cycle.
  read_server: process(clock_s) is
    variable index : natural;
  begin
    if rising_edge(clock_s) then
      if enable_s = '1' then
        rchar_s <= rd_s1_s.char;
        rul_s <= rd_s1_s.ul;
        rfg_s <= rd_s1_s.fg;
        rbg_s <= rd_s1_s.bg;
        index := to_integer(row_s) * buffer_columns_c + to_integer(column_s);
        rd_s1_s <= screen_s(index);
      end if;
    end if;
  end process;

  spy: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if enable_s = '1' and write_s = '1' then
        screen_s(to_integer(row_s) * buffer_columns_c + to_integer(column_s))
          <= cell_t'(
            char => character_s,
            fg => foreground_s,
            bg => background_s,
            ul => underline_s);
      end if;
    end if;
  end process;

  bell_counter: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if bell_s = '1' then
        bell_count_s <= bell_count_s + 1;
      end if;
    end if;
  end process;

  driver: process is
    procedure put(constant c : character) is
    begin
      data_s <= byte(to_unsigned(character'pos(c), 8));
      valid_s <= '1';
      wait until rising_edge(clock_s) and ready_s = '1';
      wait until falling_edge(clock_s);
      valid_s <= '0';
    end procedure;

    procedure puts(constant s : string) is
    begin
      for i in s'range
      loop
        put(s(i));
      end loop;
    end procedure;

    -- Feeds bytes back-to-back with valid held asserted, like a FIFO
    -- output port does
    procedure hose(constant s : string) is
    begin
      for i in s'range
      loop
        data_s <= byte(to_unsigned(character'pos(s(i)), 8));
        valid_s <= '1';
        wait until rising_edge(clock_s) and ready_s = '1';
        wait until falling_edge(clock_s);
      end loop;
      valid_s <= '0';
    end procedure;

    procedure wait_idle is
      variable count : natural := 0;
    begin
      while count < 8
      loop
        wait until rising_edge(clock_s);
        if ready_s = '1' then
          count := count + 1;
        else
          count := 0;
        end if;
      end loop;
      wait until falling_edge(clock_s);
    end procedure;

    procedure check_cell(constant srow, scol : natural;
                         constant char : character;
                         constant fg : natural := 7;
                         constant bg : natural := 0;
                         constant ul : std_ulogic := '0';
                         constant msg : string := "") is
      constant index_c : natural
        := ((to_integer(row_offset_s) + srow) mod buffer_rows_c) * buffer_columns_c
        + scol;
      variable cell : cell_t;
    begin
      cell := screen_s(index_c);
      assert cell.char = to_unsigned(character'pos(char), 8)
        report msg & ": cell " & integer'image(srow) & "," & integer'image(scol)
        & " expected char " & integer'image(character'pos(char))
        & ", got " & integer'image(to_integer(cell.char))
        severity failure;
      assert cell.fg = to_unsigned(fg, 4)
        report msg & ": cell " & integer'image(srow) & "," & integer'image(scol)
        & " expected fg " & integer'image(fg)
        & ", got " & integer'image(to_integer(cell.fg))
        severity failure;
      assert cell.bg = to_unsigned(bg, 4)
        report msg & ": cell " & integer'image(srow) & "," & integer'image(scol)
        & " expected bg " & integer'image(bg)
        & ", got " & integer'image(to_integer(cell.bg))
        severity failure;
      assert cell.ul = ul
        report msg & ": cell " & integer'image(srow) & "," & integer'image(scol)
        & " underline mismatch"
        severity failure;
    end procedure;
  begin
    valid_s <= '0';
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    -- Initial clear
    wait_idle;
    check_cell(0, 0, ' ', msg => "init");
    check_cell(9, 19, ' ', msg => "init");
    assert row_offset_s = 0 report "init: offset not zero" severity failure;

    -- Plain text
    puts("Hi");
    wait_idle;
    check_cell(0, 0, 'H', msg => "text");
    check_cell(0, 1, 'i', msg => "text");

    -- CR LF
    puts(cr_c & lf_c & "X");
    wait_idle;
    check_cell(1, 0, 'X', msg => "crlf");

    -- Wrap at end of line
    puts(cr_c & "ABCDEFGHIJKLMNOPQRSTUVWXY");
    wait_idle;
    check_cell(1, 0, 'A', msg => "wrap");
    check_cell(1, 19, 'T', msg => "wrap");
    check_cell(2, 0, 'U', msg => "wrap");
    check_cell(2, 4, 'Y', msg => "wrap");

    -- Absolute positioning
    puts(esc_c & "[5;10H" & "Q");
    wait_idle;
    check_cell(4, 9, 'Q', msg => "cup");

    -- Relative moves
    puts(esc_c & "[2A" & esc_c & "[3D" & "R");
    wait_idle;
    check_cell(2, 7, 'R', msg => "move");
    puts(esc_c & "[1B" & esc_c & "[4C" & "S");
    wait_idle;
    check_cell(3, 12, 'S', msg => "move");

    -- Clamping
    puts(esc_c & "[99;5H" & esc_c & "[1A" & "W");
    wait_idle;
    check_cell(8, 4, 'W', msg => "clamp");
    puts(esc_c & "[5;99H" & esc_c & "[1D" & "V");
    wait_idle;
    check_cell(4, 18, 'V', msg => "clamp");

    -- SGR attributes
    puts(esc_c & "[6;1H" & esc_c & "[4;33;44m" & "C");
    wait_idle;
    check_cell(5, 0, 'C', fg => 3, bg => 4, ul => '1', msg => "sgr");
    puts(esc_c & "[1;31m" & "D");
    wait_idle;
    check_cell(5, 1, 'D', fg => 9, bg => 4, ul => '1', msg => "sgr bold");
    puts(esc_c & "[0m" & "E");
    wait_idle;
    check_cell(5, 2, 'E', msg => "sgr reset");
    puts(esc_c & "[95m" & "F");
    wait_idle;
    check_cell(5, 3, 'F', fg => 13, msg => "sgr bright");
    puts(esc_c & "[7;34;42m" & "G" & esc_c & "[0m");
    wait_idle;
    check_cell(5, 4, 'G', fg => 2, bg => 4, msg => "sgr reverse");

    -- Erase in line, erasing with current background
    puts(esc_c & "[7;1H" & "0123456789");
    puts(esc_c & "[7;5H" & esc_c & "[41m" & esc_c & "[K" & esc_c & "[0m");
    wait_idle;
    check_cell(6, 3, '3', msg => "el0");
    check_cell(6, 4, ' ', bg => 1, msg => "el0");
    check_cell(6, 19, ' ', bg => 1, msg => "el0");

    puts(esc_c & "[8;1H" & "abcdefghij");
    puts(esc_c & "[8;3H" & esc_c & "[1K");
    wait_idle;
    check_cell(7, 0, ' ', msg => "el1");
    check_cell(7, 2, ' ', msg => "el1");
    check_cell(7, 3, 'd', msg => "el1");

    -- Erase in display from cursor
    puts(esc_c & "[9;1H" & "KLMNO");
    puts(esc_c & "[10;1H" & "PQRST");
    puts(esc_c & "[9;3H" & esc_c & "[J");
    wait_idle;
    check_cell(8, 1, 'L', msg => "ed0");
    check_cell(8, 2, ' ', msg => "ed0");
    check_cell(9, 0, ' ', msg => "ed0");

    -- Scroll through the ring
    puts(esc_c & "[10;1H" & lf_c & lf_c & lf_c);
    wait_idle;
    assert row_offset_s = 3 report "scroll: offset not 3" severity failure;
    check_cell(1, 9, 'Q', msg => "scroll");
    check_cell(2, 0, 'C', fg => 3, bg => 4, ul => '1', msg => "scroll");
    check_cell(5, 0, 'K', msg => "scroll");
    check_cell(7, 0, ' ', msg => "scroll clear");
    check_cell(9, 19, ' ', msg => "scroll clear");

    -- Tabulations
    puts(esc_c & "[1;1H" & ht_c & "T" & ht_c & "U" & ht_c & "V");
    wait_idle;
    check_cell(0, 8, 'T', msg => "tab");
    check_cell(0, 16, 'U', msg => "tab");
    check_cell(0, 19, 'V', msg => "tab clamp");

    -- OSC string swallowed, cursor wrapped after tab clamp
    puts(esc_c & "]0;window title" & bel_c & "W");
    wait_idle;
    check_cell(1, 0, 'W', msg => "osc");
    check_cell(1, 1, ' ', msg => "osc");

    -- Unknown or private sequences ignored
    puts(esc_c & "[?25l" & esc_c & "[6n" & "Y");
    wait_idle;
    check_cell(1, 1, 'Y', msg => "ignore");
    check_cell(1, 2, ' ', msg => "ignore");

    -- Backspace
    puts("N" & bs_c & bs_c & "M");
    wait_idle;
    check_cell(1, 2, 'N', msg => "bs");
    -- The M overwrote the N position minus one
    check_cell(1, 1, 'M', msg => "bs");

    -- Save / restore
    puts(esc_c & "[3;4H" & esc_c & "[31m" & esc_c & "7"
         & esc_c & "[8;8H" & esc_c & "[0m" & esc_c & "8" & "z");
    wait_idle;
    check_cell(2, 3, 'z', fg => 1, msg => "decsc");

    -- Full reset keeps the ring base
    puts(esc_c & "c");
    wait_idle;
    assert row_offset_s = 3 report "reset: offset changed" severity failure;
    check_cell(0, 0, ' ', msg => "reset");
    check_cell(2, 3, ' ', msg => "reset");
    check_cell(9, 19, ' ', msg => "reset");
    puts("!");
    wait_idle;
    check_cell(0, 0, '!', msg => "reset home");

    -- Replay of the board demo color scene, streamed back-to-back
    -- the way the UART FIFO delivers it
    hose(esc_c & "[2J" & esc_c & "[H"
         & esc_c & "[1;32m" & " NSL ANSI TERMINAL " & esc_c & "[0m"
         & " - demo" & cr_c & lf_c & cr_c & lf_c
         & "Std: "
         & esc_c & "[40m" & " " & esc_c & "[0m"
         & esc_c & "[41m" & " " & esc_c & "[0m"
         & esc_c & "[42m" & " " & esc_c & "[0m"
         & esc_c & "[43m" & " " & esc_c & "[0m"
         & cr_c & lf_c & "Bright: "
         & esc_c & "[100m" & " " & esc_c & "[0m"
         & esc_c & "[105m" & " " & esc_c & "[0m"
         & cr_c & lf_c);
    wait_idle;
    -- The 19-character banner wraps on this 20-column screen, so the
    -- following lines sit one row lower than on a wide display
    check_cell(0, 1, 'N', fg => 10, msg => "hose");
    check_cell(1, 0, '-', msg => "hose");
    check_cell(3, 0, 'S', msg => "hose");
    check_cell(3, 5, ' ', bg => 0, msg => "hose");
    check_cell(3, 6, ' ', bg => 1, msg => "hose");
    check_cell(3, 7, ' ', bg => 2, msg => "hose");
    check_cell(3, 8, ' ', bg => 3, msg => "hose");
    check_cell(4, 0, 'B', msg => "hose");
    check_cell(4, 8, ' ', bg => 8, msg => "hose");
    check_cell(4, 9, ' ', bg => 13, msg => "hose");

    -- Character insert/delete, with attributes moving along
    puts(esc_c & "c");
    puts(esc_c & "[2;1H" & esc_c & "[32m" & "ABCDEFGHIJ" & esc_c & "[0m");
    puts(esc_c & "[2;3H" & esc_c & "[44m" & esc_c & "[2P" & esc_c & "[0m");
    wait_idle;
    -- The tail shifts left keeping its own colors; only the two
    -- vacated columns at the right get the current background
    check_cell(1, 0, 'A', fg => 2, msg => "dch");
    check_cell(1, 1, 'B', fg => 2, msg => "dch");
    check_cell(1, 2, 'E', fg => 2, msg => "dch");
    check_cell(1, 7, 'J', fg => 2, msg => "dch");
    check_cell(1, 8, ' ', bg => 0, msg => "dch shifted blank");
    check_cell(1, 18, ' ', bg => 4, msg => "dch fill");
    check_cell(1, 19, ' ', bg => 4, msg => "dch fill");

    puts(esc_c & "[44m" & esc_c & "[3@" & esc_c & "[0m");
    wait_idle;
    -- Three blanks with the current background open at the cursor,
    -- the tail shifts right keeping its colors
    check_cell(1, 2, ' ', bg => 4, msg => "ich fill");
    check_cell(1, 4, ' ', bg => 4, msg => "ich fill");
    check_cell(1, 5, 'E', fg => 2, msg => "ich");
    check_cell(1, 10, 'J', fg => 2, msg => "ich");
    check_cell(1, 11, ' ', bg => 0, msg => "ich shifted blank");

    -- Line insert/delete
    puts(esc_c & "c");
    puts(esc_c & "[2;1H" & "R1" & cr_c & lf_c & "R2" & cr_c & lf_c
         & "R3" & cr_c & lf_c & "R4");
    puts(esc_c & "[2;1H" & esc_c & "[2M");
    wait_idle;
    check_cell(1, 0, 'R', msg => "dl");
    check_cell(1, 1, '3', msg => "dl");
    check_cell(2, 1, '4', msg => "dl");
    check_cell(3, 0, ' ', msg => "dl fill");
    check_cell(4, 0, ' ', msg => "dl fill");

    puts(esc_c & "[1L");
    wait_idle;
    check_cell(1, 0, ' ', msg => "il fill");
    check_cell(2, 1, '3', msg => "il");
    check_cell(3, 1, '4', msg => "il");
    check_cell(4, 0, ' ', msg => "il");

    -- Overlong counts degrade to fills
    puts(esc_c & "[2;1H" & "XY" & esc_c & "[2;2H" & esc_c & "[99P");
    wait_idle;
    check_cell(1, 0, 'X', msg => "dch clamp");
    check_cell(1, 1, ' ', msg => "dch clamp");
    check_cell(1, 19, ' ', msg => "dch clamp");

    puts(esc_c & "[9;1H" & "WW" & esc_c & "[9;1H" & esc_c & "[99L");
    wait_idle;
    check_cell(8, 0, ' ', msg => "il clamp");
    check_cell(9, 0, ' ', msg => "il clamp");

    -- Reverse index at the top scrolls the ring down
    puts(esc_c & "c" & "TOP");
    puts(esc_c & "[1;1H" & esc_c & "M");
    wait_idle;
    assert row_offset_s = 2 report "ri: offset not 2" severity failure;
    check_cell(1, 0, 'T', msg => "ri");
    check_cell(1, 2, 'P', msg => "ri");
    check_cell(0, 0, ' ', msg => "ri fill");

    -- Cursor display: underline of the cell under the cursor toggles
    -- with the blink phase, and is restored before any write
    puts(esc_c & "c" & "AB" & esc_c & "[1;2H");
    wait_idle;
    blink_s <= '1';
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 1, 'B', ul => '1', msg => "cursor drawn");
    blink_s <= '0';
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 1, 'B', ul => '0', msg => "cursor blanked");
    blink_s <= '1';
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 1, 'B', ul => '1', msg => "cursor redrawn");

    puts("Z");
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 1, 'Z', ul => '0', msg => "cursor restored before write");
    check_cell(0, 2, ' ', ul => '1', msg => "cursor follows");

    puts(esc_c & "[?25l");
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 2, ' ', ul => '0', msg => "cursor hidden");
    puts(esc_c & "[?25h");
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 2, ' ', ul => '1', msg => "cursor shown");
    blink_s <= '0';
    for i in 1 to 12 loop wait until rising_edge(clock_s); end loop;
    wait until falling_edge(clock_s);
    check_cell(0, 2, ' ', ul => '0', msg => "cursor final undraw");

    -- Device status and attribute replies
    reply_clear_s <= '1';
    wait until rising_edge(clock_s);
    reply_clear_s <= '0';
    puts(esc_c & "c" & esc_c & "[5;7H" & esc_c & "[6n");
    wait_idle;
    for i in 1 to 4 loop wait until rising_edge(clock_s); end loop;
    assert reply_capture_s(1 to reply_len_s) = esc_c & "[5;7R"
      report "cpr: got '" & reply_capture_s(1 to reply_len_s) & "'"
      severity failure;

    -- The size probe scripts do: save cursor, reset margins, move
    -- far out of screen (must clamp to the bottom-right corner),
    -- query the position, restore.  Two-digit values must come
    -- without leading zeros.
    reply_clear_s <= '1';
    wait until rising_edge(clock_s);
    reply_clear_s <= '0';
    puts(esc_c & "7" & esc_c & "[r" & esc_c & "[9999;9999H" & esc_c & "[6n"
         & esc_c & "8");
    wait_idle;
    for i in 1 to 4 loop wait until rising_edge(clock_s); end loop;
    assert reply_capture_s(1 to reply_len_s) = esc_c & "[10;20R"
      report "size probe: got '" & reply_capture_s(1 to reply_len_s) & "'"
      severity failure;

    -- Deferred auto-wrap: printing in the last column leaves the
    -- cursor on it, and the wrap only happens when the next printable
    -- arrives.
    puts(esc_c & "c" & "ABCDEFGHIJKLMNOPQRST");
    wait_idle;
    check_cell(0, 19, 'T', msg => "wrap: last column written");
    check_cell(1, 0, ' ', msg => "wrap: no eager wrap");

    reply_clear_s <= '1';
    wait until rising_edge(clock_s);
    reply_clear_s <= '0';
    puts(esc_c & "[6n");
    wait_idle;
    for i in 1 to 4 loop wait until rising_edge(clock_s); end loop;
    assert reply_capture_s(1 to reply_len_s) = esc_c & "[1;20R"
      report "wrap: cursor left the last column, got '"
      & reply_capture_s(1 to reply_len_s) & "'"
      severity failure;

    puts("U");
    wait_idle;
    check_cell(1, 0, 'U', msg => "wrap: deferred to next printable");

    -- Carriage return cancels a pending wrap
    puts(esc_c & "c" & "ABCDEFGHIJKLMNOPQRST" & cr_c & "Z");
    wait_idle;
    check_cell(0, 0, 'Z', msg => "wrap: CR cancels the pending wrap");
    check_cell(1, 0, ' ', msg => "wrap: no wrap after CR");

    -- Filling the bottom-right corner must not scroll until the next
    -- printable arrives
    puts(esc_c & "c" & "TOP" & esc_c & "[10;1H" & "abcdefghijklmnopqrst");
    wait_idle;
    check_cell(0, 0, 'T', msg => "wrap: corner write did not scroll");
    check_cell(9, 19, 't', msg => "wrap: corner written");

    puts("x");
    wait_idle;
    check_cell(0, 0, ' ', msg => "wrap: deferred corner scroll");
    check_cell(9, 0, 'x', msg => "wrap: first column after corner scroll");

    -- An SGR at the end of a full line must not disturb the pending
    -- wrap
    puts(esc_c & "c" & "ABCDEFGHIJKLMNOPQRS"
         & esc_c & "[31mT" & esc_c & "[32mU" & esc_c & "[0m");
    wait_idle;
    check_cell(0, 19, 'T', fg => 1, msg => "wrap: colored last column");
    check_cell(1, 0, 'U', fg => 2, msg => "wrap: pending survives SGR");

    -- A line feed while the wrap is pending is the wrap itself: a
    -- full-width line followed by a newline advances a single line
    puts(esc_c & "c" & "ABCDEFGHIJKLMNOPQRST" & lf_c & "V");
    wait_idle;
    check_cell(1, 0, 'V', msg => "wrap: eaten newline");
    check_cell(2, 0, ' ', msg => "wrap: no double line advance");

    -- Same with the usual CR LF pair
    puts(esc_c & "c" & "ABCDEFGHIJKLMNOPQRST" & cr_c & lf_c & "W");
    wait_idle;
    check_cell(1, 0, 'W', msg => "wrap: full line plus crlf");
    check_cell(2, 0, ' ', msg => "wrap: no double line advance on crlf");

    reply_clear_s <= '1';
    wait until rising_edge(clock_s);
    reply_clear_s <= '0';
    puts(esc_c & "[5n");
    wait_idle;
    for i in 1 to 4 loop wait until rising_edge(clock_s); end loop;
    assert reply_capture_s(1 to reply_len_s) = esc_c & "[0n"
      report "dsr5: got '" & reply_capture_s(1 to reply_len_s) & "'"
      severity failure;

    reply_clear_s <= '1';
    wait until rising_edge(clock_s);
    reply_clear_s <= '0';
    puts(esc_c & "[c");
    wait_idle;
    for i in 1 to 4 loop wait until rising_edge(clock_s); end loop;
    assert reply_capture_s(1 to reply_len_s) = esc_c & "[?6c"
      report "da: got '" & reply_capture_s(1 to reply_len_s) & "'"
      severity failure;

    -- Scroll region: mark rows, set a sub-region, scroll inside it
    -- Rows 1-based 3..6 form the region; 2 is above, 7 below.
    puts(esc_c & "c");
    puts(esc_c & "[2;1HX");
    puts(esc_c & "[3;1HA");
    puts(esc_c & "[4;1HB");
    puts(esc_c & "[5;1HC");
    puts(esc_c & "[6;1HD");
    puts(esc_c & "[7;1HY");
    puts(esc_c & "[3;6r");           -- set region rows 3..6
    puts(esc_c & "[6;1H" & lf_c);    -- LF at bottom margin -> scroll up
    wait_idle;
    check_cell(1, 0, 'X', msg => "stbm above");
    check_cell(2, 0, 'B', msg => "stbm up");
    check_cell(3, 0, 'C', msg => "stbm up");
    check_cell(4, 0, 'D', msg => "stbm up");
    check_cell(5, 0, ' ', msg => "stbm up fill");
    check_cell(6, 0, 'Y', msg => "stbm below");

    -- Reverse index at the top margin scrolls the region down
    puts(esc_c & "[3;1H" & esc_c & "M");
    wait_idle;
    check_cell(1, 0, 'X', msg => "stbm ri above");
    check_cell(2, 0, ' ', msg => "stbm ri fill");
    check_cell(3, 0, 'B', msg => "stbm ri down");
    check_cell(4, 0, 'C', msg => "stbm ri down");
    check_cell(5, 0, 'D', msg => "stbm ri down");
    check_cell(6, 0, 'Y', msg => "stbm ri below");

    -- Delete-line stays within the region
    puts(esc_c & "[4;1H" & esc_c & "[1M");
    wait_idle;
    check_cell(2, 0, ' ', msg => "stbm dl top kept");
    check_cell(3, 0, 'C', msg => "stbm dl");
    check_cell(4, 0, 'D', msg => "stbm dl");
    check_cell(5, 0, ' ', msg => "stbm dl fill");
    check_cell(6, 0, 'Y', msg => "stbm dl below");

    -- Reset region to full screen; LF at the last row rolls the ring
    puts(esc_c & "[r");
    puts(esc_c & "[10;1HZ");
    for i in 0 to 3 loop
      wait until rising_edge(clock_s);
    end loop;
    put(lf_c);
    wait_idle;
    check_cell(8, 0, 'Z', msg => "region reset ring scroll");
    check_cell(9, 0, ' ', msg => "region reset new row");

    -- BEL strobes the bell and prints nothing
    assert bell_count_s = 0 report "bell fired early" severity failure;
    puts(esc_c & "[1;1H" & bel_c & bel_c & "K");
    wait_idle;
    assert bell_count_s = 2
      report "bell: expected 2 pulses, got " & integer'image(bell_count_s)
      severity failure;
    check_cell(0, 0, 'K', msg => "bell prints nothing before K");

    -- Local echo (SRM): off by default, CSI 12 l enables, 12 h clears
    assert local_echo_s = '0' report "local echo on by default" severity failure;
    puts(esc_c & "[12l");
    wait_idle;
    assert local_echo_s = '1' report "SRM reset did not enable local echo" severity failure;
    puts(esc_c & "[12h");
    wait_idle;
    assert local_echo_s = '0' report "SRM set did not disable local echo" severity failure;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 ms;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
