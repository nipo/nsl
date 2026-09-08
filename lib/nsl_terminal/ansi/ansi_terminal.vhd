library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

entity ansi_terminal is
  generic(
    row_count_c : positive;
    column_count_c : positive;
    row_count_l2_c : positive;
    column_count_l2_c : positive;
    character_count_l2_c : positive := 8;
    default_foreground_c : natural := 7;
    default_background_c : natural := 0;
    -- Cycles from a buffer read address to its data, matching the
    -- backing memory. The cursor and in-place editing wait this long
    -- before writing back.
    read_latency_c : positive := 1
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i : in std_ulogic;
    ready_o : out std_ulogic;
    data_i : in nsl_data.bytestream.byte;

    -- Cursor blink phase: the cursor is shown while high, hidden
    -- while low. Tie high for a solid cursor.
    cursor_blink_i : in std_ulogic := '1';

    -- Reply byte stream, answers to DSR and DA queries. Typically
    -- fed to the host UART TX.
    reply_valid_o : out std_ulogic;
    reply_ready_i : in std_ulogic := '1';
    reply_data_o : out nsl_data.bytestream.byte;

    -- Strobed for one cycle when a BEL (0x07) is consumed, to drive an
    -- audible or visual bell.
    bell_o : out std_ulogic;

    -- Local echo request, driven by the SRM mode (CSI 12 l sets it,
    -- CSI 12 h clears it). High means the integration should loop the
    -- input keystrokes back into this engine's byte stream.
    local_echo_o : out std_ulogic;

    row_offset_o : out unsigned(row_count_l2_c-1 downto 0);

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
end entity;

architecture beh of ansi_terminal is

  subtype row_t is unsigned(row_count_l2_c-1 downto 0);
  subtype column_t is unsigned(column_count_l2_c-1 downto 0);
  subtype param_t is unsigned(7 downto 0);
  subtype color_t is unsigned(3 downto 0);

  constant last_row_c : row_t := to_unsigned(row_count_c - 1, row_count_l2_c);
  constant last_column_c : column_t := to_unsigned(column_count_c - 1, column_count_l2_c);
  constant default_fg_c : color_t := to_unsigned(default_foreground_c, 4);
  constant default_bg_c : color_t := to_unsigned(default_background_c, 4);

  -- Parameters saturate at 255; accumulation goes through this table
  -- to avoid a x10 carry chain.
  type mul10_t is array(0 to 24) of param_t;
  function mul10_precalc return mul10_t is
    variable ret : mul10_t;
  begin
    for i in ret'range
    loop
      ret(i) := to_unsigned(i * 10, 8);
    end loop;
    return ret;
  end function;
  constant mul10_c : mul10_t := mul10_precalc;

  type param_vector is array(0 to 3) of param_t;

  type state_t is (
    -- Byte-consuming parser states
    ST_GROUND,
    ST_ESCAPE,
    ST_ESCAPE_SWALLOW,
    ST_CSI,
    ST_CSI_IGNORE,
    ST_STRING,
    ST_STRING_ESC,
    -- Multi-cycle operations, input stream stalled
    ST_FILL,
    ST_MOVE,
    ST_SGR,
    ST_EDIT_LAUNCH,
    ST_COPY,
    ST_CURSOR,
    ST_REPLY
    );

  constant reply_max_c : natural := 12;
  type reply_buffer_t is array(0 to reply_max_c-1) of param_t;

  -- Fills the escape+decimals of a cursor position report. Positions
  -- are 1-based and emitted with the minimal digit count, like
  -- hardware terminals do: size-probing scripts choke on leading
  -- zeros (a shell reading "048" parses it as bad octal).
  function decimal_length(v : natural) return natural is
  begin
    if v >= 100 then
      return 3;
    elsif v >= 10 then
      return 2;
    else
      return 1;
    end if;
  end function;

  function cpr_reply(row, col : natural) return reply_buffer_t is
    variable ret : reply_buffer_t := (others => (others => '0'));
    variable rv : natural := row + 1;
    variable cv : natural := col + 1;
    variable i : natural := 2;
  begin
    ret(0) := to_unsigned(16#1b#, 8);
    ret(1) := to_unsigned(16#5b#, 8);
    if rv >= 100 then
      ret(i) := to_unsigned(16#30# + (rv / 100) mod 10, 8);
      i := i + 1;
    end if;
    if rv >= 10 then
      ret(i) := to_unsigned(16#30# + (rv / 10) mod 10, 8);
      i := i + 1;
    end if;
    ret(i) := to_unsigned(16#30# + rv mod 10, 8);
    i := i + 1;
    ret(i) := to_unsigned(16#3b#, 8);
    i := i + 1;
    if cv >= 100 then
      ret(i) := to_unsigned(16#30# + (cv / 100) mod 10, 8);
      i := i + 1;
    end if;
    if cv >= 10 then
      ret(i) := to_unsigned(16#30# + (cv / 10) mod 10, 8);
      i := i + 1;
    end if;
    ret(i) := to_unsigned(16#30# + cv mod 10, 8);
    i := i + 1;
    ret(i) := to_unsigned(16#52#, 8);
    return ret;
  end function;

  function cpr_reply_length(row, col : natural) return natural is
  begin
    return 4 + decimal_length(row + 1) + decimal_length(col + 1);
  end function;

  type direction_t is (
    DIR_UP,
    DIR_DOWN,
    DIR_LEFT,
    DIR_RIGHT
    );

  type edit_kind_t is (
    EDIT_ICH,
    EDIT_DCH,
    EDIT_IL,
    EDIT_DL
    );

  type regs_t is
  record
    state : state_t;

    row : row_t;
    col : column_t;
    -- Deferred auto-wrap: set after printing in the last column, the
    -- cursor stays put and the wrap happens when the next printable
    -- arrives.  Cursor motion cancels it.
    wrap_pending : std_ulogic;
    base : row_t;

    fg, bg : color_t;
    underline, bold, reverse : std_ulogic;

    s_row : row_t;
    s_col : column_t;
    s_fg, s_bg : color_t;
    s_underline, s_bold, s_reverse : std_ulogic;

    params : param_vector;
    param_idx : natural range 0 to 3;
    csi_private : boolean;

    fill_row, fill_end_row : row_t;
    fill_col, fill_end_col : column_t;

    move_left : param_t;
    move_next : param_t;
    move_dir : direction_t;

    sgr_idx : natural range 0 to 3;

    -- Insert/delete operation, registered at dispatch so every
    -- computation stays a single addition
    edit_kind : edit_kind_t;
    op_shift : param_t;
    op_rem_m1 : param_t;
    -- Row span line insert/delete and region scroll operate on
    edit_top, edit_bottom : row_t;
    copy_src_row, copy_dst_row, copy_end_row : row_t;
    copy_src_col, copy_dst_col, copy_end_col : column_t;
    copy_backward : boolean;
    copy_write : boolean;
    rmw_wait : natural range 0 to read_latency_c - 1;
    edit_fill_row : row_t;
    edit_fill_col : column_t;

    -- Scroll region margins, inclusive screen rows
    margin_top, margin_bottom : row_t;

    cursor_drawn : boolean;
    cursor_enable : std_ulogic;
    local_echo : std_ulogic;

    reply : reply_buffer_t;
    reply_len : natural range 0 to reply_max_c;
    reply_idx : natural range 0 to reply_max_c;
  end record;

  signal r, rin : regs_t;

begin

  assert row_count_c <= 2 ** row_count_l2_c
    report "Visible rows do not fit the buffer"
    severity failure;
  assert column_count_c <= 2 ** column_count_l2_c
    report "Visible columns do not fit the buffer"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_FILL;
      r.fill_row <= (others => '0');
      r.fill_col <= (others => '0');
      r.fill_end_row <= last_row_c;
      r.fill_end_col <= last_column_c;
      r.row <= (others => '0');
      r.col <= (others => '0');
      r.base <= (others => '0');
      r.fg <= default_fg_c;
      r.bg <= default_bg_c;
      r.underline <= '0';
      r.bold <= '0';
      r.reverse <= '0';
      r.s_row <= (others => '0');
      r.s_col <= (others => '0');
      r.s_fg <= default_fg_c;
      r.s_bg <= default_bg_c;
      r.s_underline <= '0';
      r.s_bold <= '0';
      r.s_reverse <= '0';
      r.params <= (others => (others => '0'));
      r.param_idx <= 0;
      r.csi_private <= false;
      r.move_left <= (others => '0');
      r.move_next <= (others => '0');
      r.move_dir <= DIR_UP;
      r.sgr_idx <= 0;
      r.edit_kind <= EDIT_ICH;
      r.op_shift <= (others => '0');
      r.op_rem_m1 <= (others => '0');
      r.edit_top <= (others => '0');
      r.edit_bottom <= last_row_c;
      r.margin_top <= (others => '0');
      r.margin_bottom <= last_row_c;
      r.copy_src_row <= (others => '0');
      r.copy_dst_row <= (others => '0');
      r.copy_end_row <= (others => '0');
      r.copy_src_col <= (others => '0');
      r.copy_dst_col <= (others => '0');
      r.copy_end_col <= (others => '0');
      r.copy_backward <= false;
      r.copy_write <= false;
      r.rmw_wait <= 0;
      r.edit_fill_row <= (others => '0');
      r.edit_fill_col <= (others => '0');
      r.cursor_drawn <= false;
      r.cursor_enable <= '1';
      r.local_echo <= '0';
      r.wrap_pending <= '0';
      r.reply <= (others => (others => '0'));
      r.reply_len <= 0;
      r.reply_idx <= 0;
    end if;
  end process;

  transition: process(r, valid_i, data_i, cursor_blink_i, reply_ready_i) is
    variable data_v : param_t;
    -- Parameters with their "default 1" semantics, minus one
    variable p0_m1, p1_m1 : param_t;
    variable sgr_v : param_t;
    variable shift_row_v : row_t;
    variable shift_col_v : column_t;
    variable new_top_v, new_bottom_v : row_t;

    -- Scrolls the region up by one line, clearing the incoming bottom
    -- row. A full-screen region rolls the ring; a sub-region copies
    -- rows in place.
    procedure region_scroll_up is
    begin
      if r.margin_top = 0 and r.margin_bottom = last_row_c then
        rin.base <= r.base + 1;
        rin.state <= ST_FILL;
        rin.fill_row <= last_row_c;
        rin.fill_col <= (others => '0');
        rin.fill_end_row <= last_row_c;
        rin.fill_end_col <= last_column_c;
      else
        rin.state <= ST_EDIT_LAUNCH;
        rin.edit_kind <= EDIT_DL;
        rin.edit_top <= r.margin_top;
        rin.edit_bottom <= r.margin_bottom;
        rin.op_shift <= to_unsigned(1, 8);
        rin.op_rem_m1 <= resize(r.margin_bottom - r.margin_top, 8);
      end if;
    end procedure;

    -- Scrolls the region down by one line, clearing the incoming top
    -- row.
    procedure region_scroll_down is
    begin
      if r.margin_top = 0 and r.margin_bottom = last_row_c then
        rin.base <= r.base - 1;
        rin.state <= ST_FILL;
        rin.fill_row <= (others => '0');
        rin.fill_col <= (others => '0');
        rin.fill_end_row <= (others => '0');
        rin.fill_end_col <= last_column_c;
      else
        rin.state <= ST_EDIT_LAUNCH;
        rin.edit_kind <= EDIT_IL;
        rin.edit_top <= r.margin_top;
        rin.edit_bottom <= r.margin_bottom;
        rin.op_shift <= to_unsigned(1, 8);
        rin.op_rem_m1 <= resize(r.margin_bottom - r.margin_top, 8);
      end if;
    end procedure;

    -- Line feed: move down one row, scrolling the region when at its
    -- bottom margin.
    procedure line_feed is
    begin
      if r.row = r.margin_bottom then
        region_scroll_up;
      elsif r.row /= last_row_c then
        rin.row <= r.row + 1;
      end if;
    end procedure;

    -- Reverse line feed: move up one row, scrolling the region down
    -- when at its top margin.
    procedure reverse_line_feed is
    begin
      if r.row = r.margin_top then
        region_scroll_down;
      elsif r.row /= 0 then
        rin.row <= r.row - 1;
      end if;
    end procedure;
  begin
    rin <= r;

    data_v := unsigned(data_i);

    if r.params(0) = 0 then
      p0_m1 := to_unsigned(0, 8);
    else
      p0_m1 := r.params(0) - 1;
    end if;

    if r.params(1) = 0 then
      p1_m1 := to_unsigned(0, 8);
    else
      p1_m1 := r.params(1) - 1;
    end if;

    sgr_v := r.params(r.sgr_idx);
    shift_row_v := resize(r.op_shift, row_count_l2_c);
    shift_col_v := resize(r.op_shift, column_count_l2_c);

    case r.state is
      when ST_FILL =>
        -- The pointed cell is written by the mealy process this cycle
        if r.fill_row = r.fill_end_row and r.fill_col = r.fill_end_col then
          rin.state <= ST_GROUND;
        elsif r.fill_col /= last_column_c then
          rin.fill_col <= r.fill_col + 1;
        else
          rin.fill_col <= (others => '0');
          rin.fill_row <= r.fill_row + 1;
        end if;

      when ST_MOVE =>
        if r.move_left = 0
          or (r.move_dir = DIR_UP and r.row = 0)
          or (r.move_dir = DIR_DOWN and r.row = last_row_c)
          or (r.move_dir = DIR_LEFT and r.col = 0)
          or (r.move_dir = DIR_RIGHT and r.col = last_column_c) then
          if r.move_next /= 0 then
            rin.move_dir <= DIR_RIGHT;
            rin.move_left <= r.move_next;
            rin.move_next <= (others => '0');
          else
            rin.state <= ST_GROUND;
          end if;
        else
          rin.move_left <= r.move_left - 1;
          case r.move_dir is
            when DIR_UP => rin.row <= r.row - 1;
            when DIR_DOWN => rin.row <= r.row + 1;
            when DIR_LEFT => rin.col <= r.col - 1;
            when DIR_RIGHT => rin.col <= r.col + 1;
          end case;
        end if;

      when ST_SGR =>
        if sgr_v = 0 then
          rin.fg <= default_fg_c;
          rin.bg <= default_bg_c;
          rin.underline <= '0';
          rin.bold <= '0';
          rin.reverse <= '0';
        elsif sgr_v = 1 then
          rin.bold <= '1';
          rin.fg(3) <= '1';
        elsif sgr_v = 4 then
          rin.underline <= '1';
        elsif sgr_v = 7 then
          rin.reverse <= '1';
        elsif sgr_v = 22 then
          rin.bold <= '0';
          rin.fg(3) <= '0';
        elsif sgr_v = 24 then
          rin.underline <= '0';
        elsif sgr_v = 27 then
          rin.reverse <= '0';
        elsif sgr_v >= 30 and sgr_v <= 37 then
          rin.fg <= r.bold & resize(sgr_v - 30, 3);
        elsif sgr_v = 39 then
          rin.fg <= default_fg_c;
        elsif sgr_v >= 40 and sgr_v <= 47 then
          rin.bg <= '0' & resize(sgr_v - 40, 3);
        elsif sgr_v = 49 then
          rin.bg <= default_bg_c;
        elsif sgr_v >= 90 and sgr_v <= 97 then
          rin.fg <= '1' & resize(sgr_v - 90, 3);
        elsif sgr_v >= 100 and sgr_v <= 107 then
          rin.bg <= '1' & resize(sgr_v - 100, 3);
        end if;

        -- 38/48 take color-space parameters we cannot tell apart
        -- from attributes, drop the rest of the list
        if r.sgr_idx = r.param_idx or sgr_v = 38 or sgr_v = 48 then
          rin.state <= ST_GROUND;
        else
          rin.sgr_idx <= r.sgr_idx + 1;
        end if;

      when ST_EDIT_LAUNCH =>
        if r.op_shift > r.op_rem_m1 then
          -- Shifting everything out is a plain fill
          rin.state <= ST_FILL;
          if r.edit_kind = EDIT_ICH or r.edit_kind = EDIT_DCH then
            rin.fill_row <= r.row;
            rin.fill_col <= r.col;
            rin.fill_end_row <= r.row;
            rin.fill_end_col <= last_column_c;
          else
            rin.fill_row <= r.edit_top;
            rin.fill_col <= (others => '0');
            rin.fill_end_row <= r.edit_bottom;
            rin.fill_end_col <= last_column_c;
          end if;
        else
          rin.state <= ST_COPY;
          rin.copy_write <= false;
          rin.rmw_wait <= read_latency_c - 1;
          case r.edit_kind is
            when EDIT_DCH =>
              rin.copy_src_row <= r.row;
              rin.copy_src_col <= r.col + shift_col_v;
              rin.copy_dst_row <= r.row;
              rin.copy_dst_col <= r.col;
              rin.copy_end_row <= r.row;
              rin.copy_end_col <= last_column_c - shift_col_v;
              rin.copy_backward <= false;
              rin.edit_fill_row <= r.row;
              rin.edit_fill_col <= last_column_c;
            when EDIT_ICH =>
              rin.copy_src_row <= r.row;
              rin.copy_src_col <= last_column_c - shift_col_v;
              rin.copy_dst_row <= r.row;
              rin.copy_dst_col <= last_column_c;
              rin.copy_end_row <= r.row;
              rin.copy_end_col <= r.col + shift_col_v;
              rin.copy_backward <= true;
              rin.edit_fill_row <= r.row;
              rin.edit_fill_col <= r.col;
            when EDIT_DL =>
              rin.copy_src_row <= r.edit_top + shift_row_v;
              rin.copy_src_col <= (others => '0');
              rin.copy_dst_row <= r.edit_top;
              rin.copy_dst_col <= (others => '0');
              rin.copy_end_row <= r.edit_bottom - shift_row_v;
              rin.copy_end_col <= last_column_c;
              rin.copy_backward <= false;
              rin.edit_fill_row <= r.edit_bottom;
              rin.edit_fill_col <= last_column_c;
            when EDIT_IL =>
              rin.copy_src_row <= r.edit_bottom - shift_row_v;
              rin.copy_src_col <= last_column_c;
              rin.copy_dst_row <= r.edit_bottom;
              rin.copy_dst_col <= last_column_c;
              rin.copy_end_row <= r.edit_top + shift_row_v;
              rin.copy_end_col <= (others => '0');
              rin.copy_backward <= true;
              rin.edit_fill_row <= r.edit_top;
              rin.edit_fill_col <= (others => '0');
          end case;
        end if;

      when ST_COPY =>
        if not r.copy_write then
          -- Source read is issued; wait the memory latency before the
          -- write can consume its data
          if r.rmw_wait /= 0 then
            rin.rmw_wait <= r.rmw_wait - 1;
          else
            rin.copy_write <= true;
          end if;
        else
          rin.copy_write <= false;
          rin.rmw_wait <= read_latency_c - 1;
          if r.copy_dst_row = r.copy_end_row
            and r.copy_dst_col = r.copy_end_col then
            -- Fill the vacated cells
            rin.state <= ST_FILL;
            if r.copy_backward then
              rin.fill_row <= r.edit_fill_row;
              rin.fill_col <= r.edit_fill_col;
              if r.copy_dst_col = 0 then
                rin.fill_end_row <= r.copy_dst_row - 1;
                rin.fill_end_col <= last_column_c;
              else
                rin.fill_end_row <= r.copy_dst_row;
                rin.fill_end_col <= r.copy_dst_col - 1;
              end if;
            else
              rin.fill_end_row <= r.edit_fill_row;
              rin.fill_end_col <= r.edit_fill_col;
              if r.copy_dst_col = last_column_c then
                rin.fill_row <= r.copy_dst_row + 1;
                rin.fill_col <= (others => '0');
              else
                rin.fill_row <= r.copy_dst_row;
                rin.fill_col <= r.copy_dst_col + 1;
              end if;
            end if;
          elsif r.copy_backward then
            if r.copy_dst_col = 0 then
              rin.copy_dst_row <= r.copy_dst_row - 1;
              rin.copy_dst_col <= last_column_c;
            else
              rin.copy_dst_col <= r.copy_dst_col - 1;
            end if;
            if r.copy_src_col = 0 then
              rin.copy_src_row <= r.copy_src_row - 1;
              rin.copy_src_col <= last_column_c;
            else
              rin.copy_src_col <= r.copy_src_col - 1;
            end if;
          else
            if r.copy_dst_col = last_column_c then
              rin.copy_dst_row <= r.copy_dst_row + 1;
              rin.copy_dst_col <= (others => '0');
            else
              rin.copy_dst_col <= r.copy_dst_col + 1;
            end if;
            if r.copy_src_col = last_column_c then
              rin.copy_src_row <= r.copy_src_row + 1;
              rin.copy_src_col <= (others => '0');
            else
              rin.copy_src_col <= r.copy_src_col + 1;
            end if;
          end if;
        end if;

      when ST_CURSOR =>
        -- Toggle the underline of the cell under the cursor through a
        -- read-modify-write
        if not r.copy_write then
          if r.rmw_wait /= 0 then
            rin.rmw_wait <= r.rmw_wait - 1;
          else
            rin.copy_write <= true;
          end if;
        else
          rin.copy_write <= false;
          rin.rmw_wait <= read_latency_c - 1;
          rin.cursor_drawn <= not r.cursor_drawn;
          rin.state <= ST_GROUND;
        end if;

      when ST_REPLY =>
        if r.reply_idx = r.reply_len then
          rin.state <= ST_GROUND;
        elsif reply_ready_i = '1' then
          rin.reply_idx <= r.reply_idx + 1;
        end if;

      when ST_GROUND =>
        if r.cursor_drawn
          and (valid_i = '1' or cursor_blink_i = '0' or r.cursor_enable = '0') then
          -- Restore the cell before consuming anything or when the
          -- blink phase hides the cursor
          rin.state <= ST_CURSOR;
          rin.copy_write <= false;
          rin.rmw_wait <= read_latency_c - 1;
        elsif not r.cursor_drawn
          and r.cursor_enable = '1' and cursor_blink_i = '1' and valid_i = '0' then
          rin.state <= ST_CURSOR;
          rin.copy_write <= false;
          rin.rmw_wait <= read_latency_c - 1;
        elsif valid_i = '1' then
          if data_v = 16#1b# then
            rin.state <= ST_ESCAPE;
          elsif data_v = 16#0d# then
            rin.col <= (others => '0');
            rin.wrap_pending <= '0';
          elsif data_v = 16#0a# or data_v = 16#0b# or data_v = 16#0c# then
            -- A line feed while a wrap is pending is the wrap itself
            -- (the vt100 "eaten newline"): the cursor goes to the
            -- start of the next line, not one line down in the last
            -- column.
            line_feed;
            rin.wrap_pending <= '0';
            if r.wrap_pending = '1' then
              rin.col <= (others => '0');
            end if;
          elsif data_v = 16#08# then
            if r.col /= 0 then
              rin.col <= r.col - 1;
            end if;
            rin.wrap_pending <= '0';
          elsif data_v = 16#09# then
            rin.state <= ST_MOVE;
            rin.move_dir <= DIR_RIGHT;
            rin.move_left <= resize(to_unsigned(8, 4) - resize(r.col(2 downto 0), 4), 8);
            rin.move_next <= (others => '0');
            rin.wrap_pending <= '0';
          elsif data_v < 32 or data_v = 127 then
            null;
          elsif r.wrap_pending = '1' then
            -- Deferred wrap: the byte is not consumed (the mealy
            -- process holds ready off), only the wrap happens; the
            -- character is processed on the next pass, after any
            -- scroll the line feed starts.
            rin.wrap_pending <= '0';
            rin.col <= (others => '0');
            line_feed;
          else
            -- Printable, written by the mealy process this cycle
            if r.col /= last_column_c then
              rin.col <= r.col + 1;
            else
              rin.wrap_pending <= '1';
            end if;
          end if;
        end if;

      when others =>
        if valid_i = '1' then
          case r.state is
            when ST_ESCAPE =>
              rin.state <= ST_GROUND;
              -- Cursor-affecting plain escapes cancel a pending
              -- wrap; CSI finals decide for themselves, strings and
              -- charset selection leave it alone
              case to_integer(data_v) is
                when 16#37# | 16#38# | 16#44# | 16#45# | 16#4d# | 16#63# =>
                  rin.wrap_pending <= '0';
                when others =>
                  null;
              end case;
              case to_integer(data_v) is
                when 16#5b# => -- [
                  rin.state <= ST_CSI;
                  rin.params <= (others => (others => '0'));
                  rin.param_idx <= 0;
                  rin.sgr_idx <= 0;
                  rin.csi_private <= false;
                when 16#5d# | 16#50# | 16#58# | 16#5e# | 16#5f# => -- ] P X ^ _
                  rin.state <= ST_STRING;
                when 16#28# | 16#29# => -- ( )
                  rin.state <= ST_ESCAPE_SWALLOW;
                when 16#37# => -- 7
                  rin.s_row <= r.row;
                  rin.s_col <= r.col;
                  rin.s_fg <= r.fg;
                  rin.s_bg <= r.bg;
                  rin.s_underline <= r.underline;
                  rin.s_bold <= r.bold;
                  rin.s_reverse <= r.reverse;
                when 16#38# => -- 8
                  rin.row <= r.s_row;
                  rin.col <= r.s_col;
                  rin.fg <= r.s_fg;
                  rin.bg <= r.s_bg;
                  rin.underline <= r.s_underline;
                  rin.bold <= r.s_bold;
                  rin.reverse <= r.s_reverse;
                when 16#44# | 16#45# => -- D (index), E (next line)
                  if data_v = 16#45# then
                    rin.col <= (others => '0');
                  end if;
                  line_feed;
                when 16#4d# => -- M (reverse index)
                  reverse_line_feed;
                when 16#63# => -- c
                  rin.fg <= default_fg_c;
                  rin.bg <= default_bg_c;
                  rin.underline <= '0';
                  rin.bold <= '0';
                  rin.reverse <= '0';
                  rin.row <= (others => '0');
                  rin.col <= (others => '0');
                  rin.cursor_enable <= '1';
                  rin.local_echo <= '0';
                  rin.margin_top <= (others => '0');
                  rin.margin_bottom <= last_row_c;
                  rin.state <= ST_FILL;
                  rin.fill_row <= (others => '0');
                  rin.fill_col <= (others => '0');
                  rin.fill_end_row <= last_row_c;
                  rin.fill_end_col <= last_column_c;
                when others =>
                  null;
              end case;

            when ST_ESCAPE_SWALLOW =>
              rin.state <= ST_GROUND;

            when ST_CSI =>
              if data_v >= 16#30# and data_v <= 16#39# then
                if r.params(r.param_idx) > 24 then
                  rin.params(r.param_idx) <= to_unsigned(255, 8);
                else
                  rin.params(r.param_idx)
                    <= mul10_c(to_integer(r.params(r.param_idx)))
                    + resize(data_v(3 downto 0), 8);
                end if;
              elsif data_v = 16#3b# then -- ;
                if r.param_idx /= 3 then
                  rin.param_idx <= r.param_idx + 1;
                end if;
              elsif data_v = 16#1b# then
                rin.state <= ST_ESCAPE;
              elsif data_v = 16#18# or data_v = 16#1a# then -- CAN, SUB
                rin.state <= ST_GROUND;
              elsif data_v = 16#3f# then -- ?
                rin.csi_private <= true;
              elsif data_v < 16#30# or (data_v >= 16#3c# and data_v <= 16#3e#) then
                -- Intermediates, other private markers, stray controls
                rin.state <= ST_CSI_IGNORE;
              elsif data_v = 16#3a# then -- :
                rin.state <= ST_CSI_IGNORE;
              elsif r.csi_private then
                -- Private final byte, only DECTCEM is handled
                rin.state <= ST_GROUND;
                if r.params(0) = 25 then
                  if data_v = 16#68# then -- h
                    rin.cursor_enable <= '1';
                  elsif data_v = 16#6c# then -- l
                    rin.cursor_enable <= '0';
                  end if;
                end if;
              else
                -- Final byte
                rin.state <= ST_GROUND;
                -- Every final moves or edits except attribute, mode
                -- and report ones, which keep a pending wrap intact
                if data_v /= 16#6d# and data_v /= 16#68#
                  and data_v /= 16#6c# and data_v /= 16#6e# then
                  rin.wrap_pending <= '0';
                end if;
                case to_integer(data_v) is
                  when 16#41# => -- A
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_UP;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#42# | 16#65# => -- B, e
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_DOWN;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#43# | 16#61# => -- C, a
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_RIGHT;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#44# => -- D
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_LEFT;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#45# => -- E
                    rin.col <= (others => '0');
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_DOWN;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#46# => -- F
                    rin.col <= (others => '0');
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_UP;
                    rin.move_left <= p0_m1 + 1;
                    rin.move_next <= (others => '0');
                  when 16#47# | 16#60# => -- G, `
                    rin.col <= (others => '0');
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_RIGHT;
                    rin.move_left <= p0_m1;
                    rin.move_next <= (others => '0');
                  when 16#64# => -- d
                    rin.row <= (others => '0');
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_DOWN;
                    rin.move_left <= p0_m1;
                    rin.move_next <= (others => '0');
                  when 16#48# | 16#66# => -- H, f
                    rin.row <= (others => '0');
                    rin.col <= (others => '0');
                    rin.state <= ST_MOVE;
                    rin.move_dir <= DIR_DOWN;
                    rin.move_left <= p0_m1;
                    rin.move_next <= p1_m1;
                  when 16#4a# => -- J
                    rin.state <= ST_FILL;
                    if r.params(0) = 0 then
                      rin.fill_row <= r.row;
                      rin.fill_col <= r.col;
                      rin.fill_end_row <= last_row_c;
                      rin.fill_end_col <= last_column_c;
                    elsif r.params(0) = 1 then
                      rin.fill_row <= (others => '0');
                      rin.fill_col <= (others => '0');
                      rin.fill_end_row <= r.row;
                      rin.fill_end_col <= r.col;
                    else
                      rin.fill_row <= (others => '0');
                      rin.fill_col <= (others => '0');
                      rin.fill_end_row <= last_row_c;
                      rin.fill_end_col <= last_column_c;
                    end if;
                  when 16#4b# => -- K
                    rin.state <= ST_FILL;
                    rin.fill_row <= r.row;
                    rin.fill_end_row <= r.row;
                    if r.params(0) = 0 then
                      rin.fill_col <= r.col;
                      rin.fill_end_col <= last_column_c;
                    elsif r.params(0) = 1 then
                      rin.fill_col <= (others => '0');
                      rin.fill_end_col <= r.col;
                    else
                      rin.fill_col <= (others => '0');
                      rin.fill_end_col <= last_column_c;
                    end if;
                  when 16#40# => -- @
                    rin.state <= ST_EDIT_LAUNCH;
                    rin.edit_kind <= EDIT_ICH;
                    rin.op_shift <= p0_m1 + 1;
                    rin.op_rem_m1 <= resize(last_column_c - r.col, 8);
                  when 16#50# => -- P
                    rin.state <= ST_EDIT_LAUNCH;
                    rin.edit_kind <= EDIT_DCH;
                    rin.op_shift <= p0_m1 + 1;
                    rin.op_rem_m1 <= resize(last_column_c - r.col, 8);
                  when 16#4c# => -- L, insert lines within the region
                    rin.state <= ST_EDIT_LAUNCH;
                    rin.edit_kind <= EDIT_IL;
                    rin.edit_top <= r.row;
                    rin.edit_bottom <= r.margin_bottom;
                    rin.op_shift <= p0_m1 + 1;
                    rin.op_rem_m1 <= resize(r.margin_bottom - r.row, 8);
                  when 16#4d# => -- M, delete lines within the region
                    rin.state <= ST_EDIT_LAUNCH;
                    rin.edit_kind <= EDIT_DL;
                    rin.edit_top <= r.row;
                    rin.edit_bottom <= r.margin_bottom;
                    rin.op_shift <= p0_m1 + 1;
                    rin.op_rem_m1 <= resize(r.margin_bottom - r.row, 8);
                  when 16#68# => -- h, set mode (SM)
                    -- SRM set: local echo off (the host echoes)
                    if r.params(0) = 12 then
                      rin.local_echo <= '0';
                    end if;
                  when 16#6c# => -- l, reset mode (RM)
                    -- SRM reset: local echo on
                    if r.params(0) = 12 then
                      rin.local_echo <= '1';
                    end if;
                  when 16#6d# => -- m
                    rin.state <= ST_SGR;
                    rin.sgr_idx <= 0;
                  when 16#73# => -- s
                    rin.s_row <= r.row;
                    rin.s_col <= r.col;
                  when 16#75# => -- u
                    rin.row <= r.s_row;
                    rin.col <= r.s_col;
                  when 16#72# => -- r, DECSTBM set scroll region
                    if p0_m1 >= row_count_c then
                      new_top_v := last_row_c;
                    else
                      new_top_v := resize(p0_m1, row_count_l2_c);
                    end if;
                    if r.params(1) = 0 or p1_m1 >= row_count_c then
                      new_bottom_v := last_row_c;
                    else
                      new_bottom_v := resize(p1_m1, row_count_l2_c);
                    end if;
                    -- An empty or inverted region resets to full screen
                    if new_top_v < new_bottom_v then
                      rin.margin_top <= new_top_v;
                      rin.margin_bottom <= new_bottom_v;
                    else
                      rin.margin_top <= (others => '0');
                      rin.margin_bottom <= last_row_c;
                    end if;
                    rin.row <= (others => '0');
                    rin.col <= (others => '0');
                  when 16#6e# => -- n, device status report
                    if r.params(0) = 6 then
                      rin.reply <= cpr_reply(to_integer(r.row), to_integer(r.col));
                      rin.reply_len <= cpr_reply_length(to_integer(r.row),
                                                        to_integer(r.col));
                      rin.reply_idx <= 0;
                      rin.state <= ST_REPLY;
                    elsif r.params(0) = 5 then
                      -- Terminal OK: ESC [ 0 n
                      rin.reply(0) <= to_unsigned(16#1b#, 8);
                      rin.reply(1) <= to_unsigned(16#5b#, 8);
                      rin.reply(2) <= to_unsigned(16#30#, 8);
                      rin.reply(3) <= to_unsigned(16#6e#, 8);
                      rin.reply_len <= 4;
                      rin.reply_idx <= 0;
                      rin.state <= ST_REPLY;
                    end if;
                  when 16#63# => -- c, primary device attributes
                    if r.params(0) = 0 then
                      -- Claim VT102: ESC [ ? 6 c
                      rin.reply(0) <= to_unsigned(16#1b#, 8);
                      rin.reply(1) <= to_unsigned(16#5b#, 8);
                      rin.reply(2) <= to_unsigned(16#3f#, 8);
                      rin.reply(3) <= to_unsigned(16#36#, 8);
                      rin.reply(4) <= to_unsigned(16#63#, 8);
                      rin.reply_len <= 5;
                      rin.reply_idx <= 0;
                      rin.state <= ST_REPLY;
                    end if;
                  when others =>
                    null;
                end case;
              end if;

            when ST_CSI_IGNORE =>
              if data_v = 16#1b# then
                rin.state <= ST_ESCAPE;
              elsif data_v = 16#18# or data_v = 16#1a# then
                rin.state <= ST_GROUND;
              elsif data_v >= 16#40# and data_v <= 16#7e# then
                rin.state <= ST_GROUND;
              end if;

            when ST_STRING =>
              if data_v = 16#07# then -- BEL terminates OSC
                rin.state <= ST_GROUND;
              elsif data_v = 16#1b# then
                rin.state <= ST_STRING_ESC;
              end if;

            when ST_STRING_ESC =>
              -- ESC \ is the string terminator; drop the byte in any
              -- case
              rin.state <= ST_GROUND;

            when others =>
              null;
          end case;
        end if;
    end case;
  end process;

  mealy: process(r, valid_i, data_i,
                 character_i, underline_i, foreground_i, background_i) is
    variable data_v : param_t;
    variable eff_fg, eff_bg : color_t;
  begin
    data_v := unsigned(data_i);

    if r.reverse = '1' then
      eff_fg := r.bg;
      eff_bg := r.fg;
    else
      eff_fg := r.fg;
      eff_bg := r.bg;
    end if;

    row_offset_o <= r.base;

    enable_o <= '0';
    write_o <= '0';
    row_o <= r.base + r.row;
    column_o <= r.col;
    character_o <= to_unsigned(16#20#, character_count_l2_c);
    underline_o <= '0';
    foreground_o <= eff_fg;
    background_o <= eff_bg;
    ready_o <= '0';

    reply_valid_o <= '0';
    reply_data_o <= byte(r.reply(r.reply_idx mod reply_max_c));

    bell_o <= '0';
    local_echo_o <= r.local_echo;

    case r.state is
      when ST_GROUND =>
        if not r.cursor_drawn then
          if valid_i = '1' and (data_v >= 32 and data_v /= 127) then
            -- With a wrap pending the byte is left on the port while
            -- the transition process performs the wrap.
            if r.wrap_pending = '0' then
              ready_o <= '1';
              enable_o <= '1';
              write_o <= '1';
              character_o <= resize(data_v, character_count_l2_c);
              underline_o <= r.underline;
            end if;
          else
            ready_o <= '1';
            if valid_i = '1' and data_v = 16#07# then
              bell_o <= '1';
            end if;
          end if;
        end if;

      when ST_ESCAPE | ST_ESCAPE_SWALLOW | ST_CSI | ST_CSI_IGNORE
        | ST_STRING | ST_STRING_ESC =>
        ready_o <= '1';

      when ST_FILL =>
        enable_o <= '1';
        write_o <= '1';
        row_o <= r.base + r.fill_row;
        column_o <= r.fill_col;

      when ST_COPY =>
        enable_o <= '1';
        if not r.copy_write then
          row_o <= r.base + r.copy_src_row;
          column_o <= r.copy_src_col;
        else
          write_o <= '1';
          row_o <= r.base + r.copy_dst_row;
          column_o <= r.copy_dst_col;
          character_o <= character_i;
          underline_o <= underline_i;
          foreground_o <= foreground_i;
          background_o <= background_i;
        end if;

      when ST_CURSOR =>
        enable_o <= '1';
        if r.copy_write then
          write_o <= '1';
          character_o <= character_i;
          underline_o <= not underline_i;
          foreground_o <= foreground_i;
          background_o <= background_i;
        end if;

      when ST_REPLY =>
        if r.reply_idx /= r.reply_len then
          reply_valid_o <= '1';
        end if;

      when others =>
        null;
    end case;
  end process;

end architecture;
