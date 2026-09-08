library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;

-- ANSI (ECMA-48 subset) terminal emulation
package ansi is

  -- Terminal engine backed by a text buffer memory such as
  -- nsl_dvi.terminal.terminal_text_buffer. It consumes a byte stream
  -- and drives the buffer user port with the resulting screen
  -- contents. Colors are 4-bit indices: 0-7 are the standard ANSI
  -- colors, 8-15 their bright variants (SGR bold or 90-107 codes).
  --
  -- The visible screen is row_count_c x column_count_c cells inside a
  -- power-of-two buffer. Scrolling rolls the buffer: row_offset_o
  -- must be connected to the buffer row_offset_i, and the engine only
  -- clears the incoming row, making a scroll take one row worth of
  -- writes instead of one screen.
  --
  -- The escape parser recognizes and frames every ECMA-48 sequence
  -- class (ESC, CSI with parameters, OSC/DCS/APC/PM/SOS strings) so
  -- unsupported sequences are discarded cleanly. Executed today:
  --
  -- * C0: BEL (strobes bell_o), BS, TAB (8-column stops), LF/VT/FF, CR
  -- * ESC 7 / ESC 8 (save/restore cursor and attributes), ESC D
  --   (index), ESC E (next line), ESC M (reverse index, scrolls the
  --   ring down at the top row), ESC c (reset)
  -- * CSI A/B/C/D/E/F/G/a/d/e/`: cursor motion, H/f: cursor position
  -- * CSI J / K: display / line erase, filling with current colors
  -- * CSI @ / P: insert / delete characters, L / M: insert / delete
  --   lines, all shifting in-place through the buffer read port
  -- * CSI s / u: save / restore cursor position
  -- * CSI r (DECSTBM): set the scroll region top/bottom margins; line
  --   feed, reverse index, and insert/delete lines act within it. A
  --   full-screen region scrolls through the ring, a sub-region by
  --   copying rows in place.
  -- * CSI ?25h / ?25l: cursor show / hide (DECTCEM)
  -- * CSI 5n / 6n: device status / cursor position report, CSI c:
  --   primary device attributes (VT102). Answers go out on the reply
  --   stream.
  -- * CSI 12h / 12l (SRM): local echo off / on, reported on
  --   local_echo_o.
  -- * CSI m (SGR): 0, 1, 4, 7, 22, 24, 27, 30-37, 39, 40-47, 49,
  --   90-97, 100-107. 38/48 extended color sequences abort the
  --   remaining parameter list.
  --
  -- The cursor is displayed by inverting the underline bit of its
  -- cell while cursor_blink_i is high, through a read-modify-write of
  -- the buffer; the cell is restored before any byte is processed.
  --
  -- Origin mode (DECOM) is not implemented: cursor positioning stays
  -- absolute to the screen, only scrolling honors the margins.
  component ansi_terminal is
    generic(
      -- Visible screen dimensions
      row_count_c : positive;
      column_count_c : positive;
      -- Backing buffer dimensions, log2. Buffer must be at least the
      -- visible size.
      row_count_l2_c : positive;
      column_count_l2_c : positive;
      character_count_l2_c : positive := 8;
      default_foreground_c : natural := 7;
      default_background_c : natural := 0;
      -- Cycles from a buffer read address to its data
      read_latency_c : positive := 1
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Character stream, typically from an UART
      valid_i : in std_ulogic;
      ready_o : out std_ulogic;
      data_i : in nsl_data.bytestream.byte;

      -- Cursor blink phase: shown while high, hidden while low. Tie
      -- high for a solid cursor.
      cursor_blink_i : in std_ulogic := '1';

      -- Reply byte stream, answers to DSR and DA queries
      reply_valid_o : out std_ulogic;
      reply_ready_i : in std_ulogic := '1';
      reply_data_o : out nsl_data.bytestream.byte;

      -- Strobed for one cycle when a BEL (0x07) is consumed
      bell_o : out std_ulogic;

      -- Local echo request (SRM mode): high asks the integration to
      -- loop input keystrokes back into the byte stream
      local_echo_o : out std_ulogic;

      -- Ring base of the visible screen, for the buffer video side
      row_offset_o : out unsigned(row_count_l2_c-1 downto 0);

      -- Text buffer user port
      row_o : out unsigned(row_count_l2_c-1 downto 0);
      column_o : out unsigned(column_count_l2_c-1 downto 0);
      enable_o : out std_ulogic;
      write_o : out std_ulogic;
      character_o : out unsigned(character_count_l2_c-1 downto 0);
      underline_o : out std_ulogic;
      foreground_o : out unsigned(3 downto 0);
      background_o : out unsigned(3 downto 0);
      character_i : in unsigned(character_count_l2_c-1 downto 0) := (others => '0');
      underline_i : in std_ulogic := '0';
      foreground_i : in unsigned(3 downto 0) := (others => '0');
      background_i : in unsigned(3 downto 0) := (others => '0')
      );
  end component;

end package;
