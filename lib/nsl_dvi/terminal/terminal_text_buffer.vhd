library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_math, nsl_logic, nsl_indication, nsl_memory;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_indication.font.all;

entity terminal_text_buffer is
  generic(
    row_count_l2_c: positive;
    column_count_l2_c: positive;

    character_count_l2_c : positive;

    color_palette_c : nsl_color.rgb.rgb24_vector;

    font_c: nsl_data.bytestream.byte_string;

    underline_support_c: boolean := false;

    font_hscale_c: positive := 1;
    font_vscale_c: positive := 1
    );
  port(
    video_clock_i : in  std_ulogic;
    video_reset_n_i : in std_ulogic;

    sof_i : in  std_ulogic;
    sol_i : in  std_ulogic;
    pixel_ready_i : in std_ulogic;
    pixel_valid_o : out std_ulogic;
    pixel_o : out nsl_color.rgb.rgb24;

    term_clock_i : in  std_ulogic;
    term_reset_n_i : in std_ulogic;
    
    row_i : in unsigned(row_count_l2_c-1 downto 0);
    column_i : in unsigned(column_count_l2_c-1 downto 0);

    enable_i : in std_ulogic;
    write_i : in std_ulogic;
    character_i : in unsigned(character_count_l2_c-1 downto 0);
    underline_i : in std_ulogic := '0';
    foreground_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
    background_i : in unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);

    character_o : out unsigned(character_count_l2_c-1 downto 0);
    underline_o : out std_ulogic;
    foreground_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
    background_o : out unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0)
    );
end entity;

architecture beh of terminal_text_buffer is

  constant x_font_c: byte_string(0 to font_c'length-1) := font_c;
  constant font_data_c: byte_string(0 to font_c'length-3) := x_font_c(2 to x_font_c'right);
  
  constant font_width_c: integer := to_integer(x_font_c(0));
  constant font_height_c: integer := to_integer(x_font_c(1));
  
  subtype row_t is unsigned(row_count_l2_c-1 downto 0);
  subtype column_t is unsigned(column_count_l2_c-1 downto 0);
  subtype character_t is unsigned(character_count_l2_c-1 downto 0);
  subtype color_index_t is unsigned(nsl_math.arith.log2(color_palette_c'length)-1 downto 0);
  subtype glyph_line_index_t is unsigned(font_glyph_line_index_l2(font_c)-1 downto 0);
  subtype glyph_column_index_t is unsigned(font_glyph_column_index_l2(font_c)-1 downto 0);

  subtype glyph_line_t is std_ulogic_vector(0 to font_width_c-1);
  
  -- Cell memory is the character+coloring+underline memory
  -- We have as many as characters on the screen
  subtype cell_address_t is unsigned(row_count_l2_c+column_count_l2_c-1 downto 0);
  function cell_address_pack(row: row_t; column: column_t) return cell_address_t
  is
  begin
    return row & column;
  end function;

  type cell_t is
  record
    char: character_t;
    fg, bg: color_index_t;
    underline: std_ulogic;
  end record;

  constant cell_packed_length_c: natural :=
    character_t'length
    + if_else(underline_support_c, 1, 0)
    + color_index_t'length
    + color_index_t'length;
  subtype cell_packed_t is std_ulogic_vector(cell_packed_length_c-1 downto 0);

  function cell_pack(cell: cell_t) return cell_packed_t
  is
  begin
    return if_else(underline_support_c,
                   std_ulogic_vector'(0 => cell.underline),
                   std_ulogic_vector'(""))
      & std_ulogic_vector(cell.char)
      & std_ulogic_vector(cell.fg)
      & std_ulogic_vector(cell.bg);
  end function;

  function cell_unpack(enc: cell_packed_t) return cell_t
  is
    variable ret: cell_t;
  begin
    ret.char := unsigned(enc(color_index_t'length*2+character_t'length-1
                             downto color_index_t'length*2));
    ret.fg := unsigned(enc(color_index_t'length*2-1
                           downto color_index_t'length));
    ret.bg := unsigned(enc(color_index_t'length-1 downto 0));
    ret.underline := to_logic(underline_support_c) and enc(enc'left);
    return ret;
  end function;

  -- We'll forward some data after the cell contents lookup.
  type glyph_sideband_t is
  record
    glyph_line: glyph_line_index_t;
    fg, bg: color_index_t;
    underline: std_ulogic;
  end record;

  constant glyph_sideband_length_c : natural :=
    if_else(underline_support_c, 1, 0)
    + glyph_line_index_t'length
    + color_index_t'length
    + color_index_t'length;
  subtype glyph_sideband_packed_t is std_ulogic_vector(glyph_sideband_length_c-1 downto 0);
  
  function glyph_sideband_pack(glyph_line: glyph_line_index_t;
                              cell: cell_t) return glyph_sideband_packed_t
  is
  begin
    return if_else(underline_support_c,
                   std_ulogic_vector'(0 => cell.underline),
                   std_ulogic_vector'(""))
      & std_ulogic_vector(glyph_line)
      & std_ulogic_vector(cell.fg)
      & std_ulogic_vector(cell.bg);
  end function;

  function glyph_sideband_unpack(enc: glyph_sideband_packed_t) return glyph_sideband_t
  is
    variable ret: glyph_sideband_t;
  begin
    ret.glyph_line := unsigned(enc(color_index_t'length*2+glyph_line_index_t'length-1
                                   downto color_index_t'length*2));
    ret.fg := unsigned(enc(color_index_t'length*2-1
                           downto color_index_t'length));
    ret.bg := unsigned(enc(color_index_t'length-1 downto 0));
    ret.underline := to_logic(underline_support_c) and enc(enc'left);
    return ret;
  end function;

  signal line_reset_n_s: std_ulogic;
  signal cell_scan_valid_s, cell_scan_ready_s: std_ulogic;
  signal cell_scan_data_s: cell_t;
  signal cell_glyph_line_s: glyph_line_index_t;
  
  signal glyph_line_valid_s, glyph_line_ready_s: std_ulogic;
  signal glyph_line_sideband_s: glyph_sideband_t;
  signal glyph_line_data_s: glyph_line_t;
begin

  -- Cell buffer is the character memory. It manages all the user
  -- interface on one side and streams cell data to renderer on the
  -- other side.
  --
  -- Each cell is scanned once in horizontal order (whatever the
  -- horizontal stretching factor and font width.
  --
  -- Each row scan is repeated font_height * vertical_scaling times.
  cell_buffer: block is
    signal user_cell_addr_s: cell_address_t;
    signal user_cell_wdata_s, user_cell_rdata_s, streamer_mem_rdata_s: cell_packed_t;
    signal user_rcell_s: cell_t;

    signal streamer_mem_address_s: cell_address_t;
    signal streamer_mem_en_s: std_ulogic;
  begin
    -- User side: pack/unpack memory access
    user_cell_addr_s <= cell_address_pack(row_i, column_i);
    user_cell_wdata_s <= cell_pack(cell_t'(
      char => character_i,
      fg => foreground_i,
      bg => background_i,
      underline => underline_i
      ));
    user_rcell_s <= cell_unpack(user_cell_rdata_s);
    character_o <= user_rcell_s.char;
    underline_o <= user_rcell_s.underline;
    foreground_o <= user_rcell_s.fg;
    background_o <= user_rcell_s.bg;

    memory: nsl_memory.ram.ram_2p_homogeneous
      generic map(
        addr_size_c => row_i'length + column_i'length,
        word_size_c => cell_packed_t'length,
        data_word_count_c => 1,
        registered_output_c => false,
        b_can_write_c => false
        )
      port map(
        a_clock_i => term_clock_i,
        a_enable_i => enable_i,
        a_write_en_i(0) => write_i,
        a_address_i => user_cell_addr_s,
        a_data_i => user_cell_wdata_s,
        a_data_o => user_cell_rdata_s,

        b_clock_i => video_clock_i,
        b_enable_i => streamer_mem_en_s,
        b_address_i => streamer_mem_address_s,
        b_data_o => streamer_mem_rdata_s
        );

    -- Here, generate a stream of addresses to read in the character
    -- cell memory, with matching glyph line.
    sequencer: block is
      signal scan_ready_s, scan_valid_s: std_ulogic;
      signal scan_address_s: cell_address_t;
      signal cell_packed_s: cell_packed_t;
      signal scan_glyph_line_s: glyph_line_index_t;
    begin
      scanner: block is
        type state_t is (
          ST_WAIT_SOF,
          ST_WAIT_SOL,
          ST_SOL,
          ST_STREAMING
          );

        type regs_t is
        record
          state: state_t;
          row: integer range 0 to 2**row_count_l2_c-1;
          column: integer range 0 to 2**column_count_l2_c-1;
          glyph_line: integer range 0 to font_height_c-1;
          glyph_subline: integer range 0 to font_vscale_c-1;
        end record;

        signal r, rin: regs_t;
      begin        
        regs: process(video_clock_i, video_reset_n_i) is
        begin
          if rising_edge(video_clock_i) then
            r <= rin;
          end if;

          if video_reset_n_i = '0' then
            r.state <= ST_WAIT_SOF;
          end if;
        end process;

        transition: process(r, sof_i, sol_i, scan_ready_s) is
        begin
          rin <= r;
          
          case r.state is
            when ST_WAIT_SOF =>
              null;

            when ST_WAIT_SOL =>
              if sol_i = '1' then
                rin.state <= ST_SOL;
              end if;

            when ST_SOL =>
              rin.state <= ST_STREAMING;
              rin.column <= 0;

              if r.glyph_subline /= font_vscale_c-1 then
                rin.glyph_subline <= r.glyph_subline + 1;
              elsif r.glyph_line /= font_height_c-1 then
                rin.glyph_line <= r.glyph_line + 1;
                rin.glyph_subline <= 0;
              elsif r.row /= 2**row_count_l2_c-1 then
                rin.glyph_line <= 0;
                rin.glyph_subline <= 0;
                rin.row <= r.row + 1;
              else
                rin.state <= ST_WAIT_SOF;
              end if;

            when ST_STREAMING =>
              if sol_i = '1' then
                rin.state <= ST_SOL;
              elsif scan_ready_s = '1' then
                if r.column /= 2**column_count_l2_c-1 then
                  rin.column <= r.column + 1;
                else
                  rin.state <= ST_WAIT_SOL;
                end if;
              end if;
          end case;

          if sof_i = '1' then
            rin.state <= ST_WAIT_SOL;
            rin.glyph_line <= 0;
            rin.glyph_subline <= 0;
            rin.row <= 0;
          end if;          
        end process;

        moore: process(r) is
        begin
          line_reset_n_s <= '1';
          scan_address_s <= cell_address_pack(
            to_unsigned(r.row, row_count_l2_c),
            to_unsigned(r.column, column_count_l2_c));
          scan_valid_s <= '0';
          scan_glyph_line_s <= to_unsigned(r.glyph_line, scan_glyph_line_s'length);

          case r.state is
            when ST_WAIT_SOF | ST_SOL =>
              line_reset_n_s <= '0';

            when ST_WAIT_SOL =>
              null;

            when ST_STREAMING =>
              scan_valid_s <= '1';
          end case;
        end process;
      end block;

      -- Actually perform the read and stream it to cell_scan_*
      streamer: nsl_memory.streamer.memory_streamer
        generic map(
          addr_width_c => streamer_mem_address_s'length,
          data_width_c => streamer_mem_rdata_s'length,
          sideband_width_c => scan_glyph_line_s'length
          )
        port map(
          clock_i => video_clock_i,
          reset_n_i => line_reset_n_s,

          addr_valid_i => scan_valid_s,
          addr_ready_o => scan_ready_s,
          addr_i => scan_address_s,
          sideband_i => std_ulogic_vector(scan_glyph_line_s),

          data_valid_o => cell_scan_valid_s,
          data_ready_i => cell_scan_ready_s,
          data_o => cell_packed_s,
          unsigned(sideband_o) => cell_glyph_line_s,

          mem_enable_o => streamer_mem_en_s,
          mem_address_o => streamer_mem_address_s,
          mem_data_i => streamer_mem_rdata_s
          );

      cell_scan_data_s <= cell_unpack(cell_packed_s);
    end block;
  end block;

  -- Now we have a stream of:
  -- - cell_scan_data_s:
  --   - char: the character
  --   - fg: foreground color index
  --   - bg: background color index
  --   - underline: Whether to underline
  -- - cell_glyph_line_s: the line in the glyph
  -- -> guarded by cell_scan_valid_s/cell_scan_ready_s
  cell_to_glyph_line: block is
    alias scan_valid_s: std_ulogic is cell_scan_valid_s;
    alias scan_ready_s: std_ulogic is cell_scan_ready_s;
    signal glyph_scan_char_s: character_t;
    signal glyph_scan_sideband_packed_s: glyph_sideband_packed_t;

    signal glyph_mem_char_s: character_t;
    signal glyph_mem_sideband_packed_s: glyph_sideband_packed_t;
    signal glyph_mem_sideband_s: glyph_sideband_t;
    signal glyph_mem_line_s: glyph_line_index_t;
    signal glyph_mem_en_s: std_ulogic;
    signal glyph_mem_rdata_s : glyph_line_t;

    signal glyph_line_sideband_packed_s: glyph_sideband_packed_t;
  begin
    glyph_scan_char_s <= cell_scan_data_s.char;
    glyph_scan_sideband_packed_s <= glyph_sideband_pack(
      cell_glyph_line_s,
      cell_scan_data_s);

    streamer: nsl_memory.streamer.memory_streamer
      generic map(
        addr_width_c => glyph_mem_char_s'length,
        data_width_c => glyph_mem_rdata_s'length,
        sideband_width_c => glyph_line_sideband_packed_s'length
        )
      port map(
        clock_i => video_clock_i,
        reset_n_i => line_reset_n_s,

        addr_valid_i => scan_valid_s,
        addr_ready_o => scan_ready_s,
        addr_i => glyph_scan_char_s,
        sideband_i => glyph_scan_sideband_packed_s,

        data_valid_o => glyph_line_valid_s,
        data_ready_i => glyph_line_ready_s,
        data_o => glyph_line_data_s,
        sideband_o => glyph_line_sideband_packed_s,
        
        mem_enable_o => glyph_mem_en_s,
        mem_address_o => glyph_mem_char_s,
        mem_data_i => glyph_mem_rdata_s,
        mem_sideband_o => glyph_mem_sideband_packed_s
        );
    glyph_line_sideband_s <= glyph_sideband_unpack(glyph_line_sideband_packed_s);

    glyph_mem_sideband_s <= glyph_sideband_unpack(glyph_mem_sideband_packed_s);
    glyph_mem_line_s <= glyph_mem_sideband_s.glyph_line;
    font_rom: nsl_indication.font.font_rom_glyph_line
      generic map(
        font_c => font_c
        )
      port map(
        clock_i => video_clock_i,
        reset_n_i => line_reset_n_s,

        glyph_i => glyph_mem_char_s,
        line_i => glyph_mem_line_s,
        enable_i => glyph_mem_en_s,
        line_o => glyph_mem_rdata_s
        );
  end block;  

  -- Now we have a stream of glyph lines:
  -- - glyph_line_data_s, pixels from left to right
  -- - glyph_line_sideband_s
  --   - glyph_line: The number of the line
  --   - fg, bg: Color indices
  --   - underline: Whether to underline character
  -- -> guarded by glyph_line_valid_s = glyph_line_ready_s
  renderer: block is
    type state_t is (
      ST_FILL,
      ST_RENDER
      );

    type regs_t is
    record
      state: state_t;
      pixels: glyph_line_t;
      fg, bg: nsl_color.rgb.rgb24;
      negate: boolean;
      glyph_column: integer range 0 to font_width_c-1;
      glyph_subcolumn: integer range 0 to font_hscale_c-1;
    end record;

    signal r, rin: regs_t;
  begin        
    regs: process(video_clock_i, line_reset_n_s) is
    begin
      if rising_edge(video_clock_i) then
        r <= rin;
      end if;

      if line_reset_n_s = '0' then
        r.state <= ST_FILL;
      end if;
    end process;

    transition: process(r, pixel_ready_i, glyph_line_data_s, glyph_line_sideband_s, glyph_line_valid_s) is
      variable ingress: boolean;
    begin
      rin <= r;

      ingress := false;
      
      case r.state is
        when ST_FILL =>
          if glyph_line_valid_s = '1' then
            rin.state <= ST_RENDER;
            ingress := true;
          end if;                       
          
        when ST_RENDER =>
          if pixel_ready_i = '1' then
            if r.glyph_subcolumn /= font_hscale_c-1 then
              rin.glyph_subcolumn <= r.glyph_subcolumn + 1;
            elsif r.glyph_column /= font_width_c-1 then
              rin.glyph_column <= r.glyph_column + 1;
              rin.glyph_subcolumn <= 0;
              rin.pixels <= r.pixels(1 to r.pixels'right) & '-';
            else
              ingress := true;
            end if;
          end if;
      end case;

      if ingress then
        if glyph_line_sideband_s.underline = '1'
          and glyph_line_sideband_s.glyph_line = font_height_c-1 then
          rin.pixels <= not glyph_line_data_s;
        else
          rin.pixels <= glyph_line_data_s;
        end if;
        rin.fg <= color_palette_c(to_integer(glyph_line_sideband_s.fg));
        rin.bg <= color_palette_c(to_integer(glyph_line_sideband_s.bg));
        rin.glyph_column <= 0;
        rin.glyph_subcolumn <= 0;
      end if;          
    end process;

    moore: process(r, glyph_line_sideband_s) is
    begin
      glyph_line_ready_s <= '0';
      pixel_o <= nsl_color.rgb.rgb24_black;
      pixel_valid_o <= '0';

      case r.state is
        when ST_FILL =>
          glyph_line_ready_s <= '1';

        when ST_RENDER =>
          pixel_valid_o <= '1';
          if r.pixels(0) = '1' then
            pixel_o <= r.fg;
          else
            pixel_o <= r.bg;
          end if;

          if r.glyph_subcolumn = font_hscale_c-1
            and r.glyph_column = font_width_c-1 then
            glyph_line_ready_s <= '1';
          end if;
      end case;
    end process;
  end block;
end architecture;
