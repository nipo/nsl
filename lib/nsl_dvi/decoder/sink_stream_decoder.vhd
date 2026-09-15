library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_line_coding, work;
use work.dvi.all;
use nsl_data.bytestream.all;

entity sink_stream_decoder is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;

    tmds_i : in work.dvi.symbol_vector_t;

    period_o: out work.dvi.period_t;

    pixel_o : out nsl_data.bytestream.byte_string(0 to 2);

    hsync_o : out std_ulogic;
    vsync_o : out std_ulogic;

    di_hdr_o : out std_ulogic_vector(1 downto 0);
    di_data_o : out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture beh of sink_stream_decoder is

  -- A guard band symbol is a control code the TMDS decoder has no
  -- reason to tell apart from pixel data, so it comes back as one.
  constant guard_high_c : unsigned(7 downto 0) := x"ab";
  constant guard_low_c : unsigned(7 downto 0) := x"55";

  -- Symbols a data island holds, and symbols a guard band holds.
  constant di_data_count_c : natural := 32;
  constant guard_count_c : natural := 2;

  signal de_s, terc4_s: std_ulogic_vector(0 to 2);
  subtype control_t is std_ulogic_vector(3 downto 0);
  type control_vector is array(integer range <>) of control_t;
  signal control_s: control_vector(0 to 2);
  type unsigned_vector is array(integer range <>) of unsigned(7 downto 0);
  signal channel_s: unsigned_vector(0 to 2);
  signal pixel_s: byte_string(0 to 2);

  type state_t is (
    ST_RESET,
    -- Blanking.  Syncs are carried here, and a preamble opens either
    -- of the two ways out.
    ST_CONTROL,
    ST_VIDEO_PRE,
    ST_VIDEO_GUARD,
    ST_VIDEO,
    ST_DI_PRE,
    ST_DI_GUARD,
    ST_DI_DATA,
    -- The symbol after an island's 32 is either the first of another
    -- packet the source put right behind it, or the first of the
    -- guard band closing the island.  Only that symbol says which.
    ST_DI_NEXT,
    ST_DI_TRAIL_GUARD
    );

  type regs_t is
  record
    state: state_t;
    left: natural range 0 to di_data_count_c-1;
    -- Syncs last seen, so they can be held across the periods that
    -- carry no sync at all.
    hsync, vsync: std_ulogic;
  end record;

  signal r, rin: regs_t;

  -- What the symbols currently on the channels look like.
  function is_control(de: std_ulogic_vector) return boolean
  is
  begin
    return de(0) = '0';
  end function;

  -- Preamble, which channels 1 and 2 state while channel 0 keeps
  -- carrying the syncs: video is 01, 00 and a data island is 01, 01.
  function is_video_preamble(de: std_ulogic_vector;
                             control: control_vector) return boolean
  is
  begin
    return de(0) = '0'
      and control(1)(1 downto 0) = "01"
      and control(2)(1 downto 0) = "00";
  end function;

  function is_di_preamble(de: std_ulogic_vector;
                          control: control_vector) return boolean
  is
  begin
    return de(0) = '0'
      and control(1)(1 downto 0) = "01"
      and control(2)(1 downto 0) = "01";
  end function;

  -- Video guard band, the same symbol on the outer channels and the
  -- other one in the middle.
  function is_video_guard(pixel: byte_string) return boolean
  is
  begin
    return unsigned(pixel(0)) = guard_high_c
      and unsigned(pixel(1)) = guard_low_c
      and unsigned(pixel(2)) = guard_high_c;
  end function;

  -- Whether the symbol on channel 0 carries the syncs.  A basic
  -- control word always does, and so does a TERC4 word inside a data
  -- island.  A guard band and pixel data do not: the guard band
  -- symbol of channel 0 happens to decode as a TERC4 word, which is
  -- why the period has to be taken into account rather than the
  -- symbol alone.
  function carries_sync(state: state_t;
                        de: std_ulogic_vector;
                        terc4: std_ulogic_vector) return boolean
  is
  begin
    if de(0) = '0' then
      return true;
    end if;

    case state is
      when ST_DI_PRE | ST_DI_GUARD | ST_DI_DATA | ST_DI_NEXT
        | ST_DI_TRAIL_GUARD =>
        return terc4(0) = '1';

      when others =>
        return false;
    end case;
  end function;

  -- Data island symbols carry TERC4 words on the channels a guard
  -- band would show its own symbol on, which is what tells a packet
  -- following an island apart from the guard band closing it.
  function is_di_continuation(terc4: std_ulogic_vector) return boolean
  is
  begin
    return terc4(1) = '1' and terc4(2) = '1';
  end function;

  -- Data island guard band.  Channel 0 carries the syncs as a TERC4
  -- word, so only the other two show the guard symbol.
  function is_di_guard(terc4: std_ulogic_vector;
                       pixel: byte_string) return boolean
  is
  begin
    return terc4(0) = '1'
      and unsigned(pixel(1)) = guard_low_c
      and unsigned(pixel(2)) = guard_low_c;
  end function;

begin

  channels: for i in 0 to 2
  generate
    decoder: nsl_line_coding.tmds.tmds_decoder
      port map(
        clock_i => pixel_clock_i,
        reset_n_i => reset_n_i,

        symbol_i => tmds_i(i),

        de_o => de_s(i),
        pixel_o => channel_s(i),

        terc4_o => terc4_s(i),
        control_o => control_s(i)
        );
  end generate;

  regs: process(pixel_clock_i, reset_n_i) is
  begin
    if rising_edge(pixel_clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.hsync <= '0';
      r.vsync <= '0';
    end if;
  end process;

  transition: process(r, de_s, terc4_s, control_s, pixel_s) is
  begin
    rin <= r;

    if carries_sync(r.state, de_s, terc4_s) then
      rin.hsync <= control_s(0)(0);
      rin.vsync <= control_s(0)(1);
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CONTROL;

      when ST_CONTROL =>
        if is_video_preamble(de_s, control_s) then
          rin.state <= ST_VIDEO_PRE;
        elsif is_di_preamble(de_s, control_s) then
          rin.state <= ST_DI_PRE;
        elsif not is_control(de_s) and terc4_s(0) = '0' then
          -- A DVI link states no preamble and sends no guard band, so
          -- video simply starts on the first symbol that is not a
          -- control one.
          --
          -- A TERC4 word is not one of those.  It reads as data
          -- rather than as control, so without this an island whose
          -- announcement went unheard would open a video period on its
          -- guard band and hold it for the whole island -- two guard
          -- bands and thirty two symbols of packet, turned into
          -- pixels.  A DVI link never sends one, so the only cost is
          -- the odd line whose first pixel happens to encode as one
          -- starting a pixel late.
          --
          -- A link is better off losing an island it could not follow
          -- than inventing video out of it.
          rin.state <= ST_VIDEO;
        end if;

      when ST_VIDEO_PRE =>
        -- A guard band ends the preamble.  Anything else that is not
        -- still the preamble means the source gave up on the video
        -- period it was announcing.
        if is_video_guard(pixel_s) then
          rin.state <= ST_VIDEO_GUARD;
          rin.left <= guard_count_c - 2;
        elsif not is_video_preamble(de_s, control_s) then
          rin.state <= ST_CONTROL;
        end if;

      when ST_VIDEO_GUARD =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_VIDEO;
        end if;

      when ST_VIDEO =>
        -- Video runs to the end of the line, which a control period
        -- states.
        if is_control(de_s) then
          rin.state <= ST_CONTROL;
        end if;

      when ST_DI_PRE =>
        if is_di_guard(terc4_s, pixel_s) then
          rin.state <= ST_DI_GUARD;
          rin.left <= guard_count_c - 2;
        elsif not is_di_preamble(de_s, control_s) then
          rin.state <= ST_CONTROL;
        end if;

      when ST_DI_GUARD =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_DI_DATA;
          rin.left <= di_data_count_c - 1;
        end if;

      when ST_DI_DATA =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_DI_NEXT;
        end if;

      when ST_DI_NEXT =>
        if is_di_continuation(terc4_s) then
          -- Another packet, this symbol being the first of its 32.
          rin.state <= ST_DI_DATA;
          rin.left <= di_data_count_c - 2;
        else
          rin.state <= ST_DI_TRAIL_GUARD;
          rin.left <= guard_count_c - 2;
        end if;

      when ST_DI_TRAIL_GUARD =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_CONTROL;
        end if;
    end case;
  end process;

  -- Period is stated for the symbols currently on the channels, so
  -- leaving a data period has to be seen on them rather than on the
  -- state they lead to.
  mealy: process(r, de_s, terc4_s, control_s, pixel_s) is
  begin
    case r.state is
      when ST_RESET =>
        period_o <= PERIOD_CONTROL;

      when ST_CONTROL =>
        -- The symbol that opens a preamble belongs to it, so what is
        -- reported here is what the channels currently hold rather
        -- than the blanking that led to them.
        if is_video_preamble(de_s, control_s) then
          period_o <= PERIOD_VIDEO_PRE;
        elsif is_di_preamble(de_s, control_s) then
          period_o <= PERIOD_DI_PRE;
        elsif is_control(de_s) or terc4_s(0) = '1' then
          -- Data without an announcement is video on a DVI link and
          -- an island gone astray on one that announces its periods.
          -- The state this leads to draws the same line.
          period_o <= PERIOD_CONTROL;
        else
          period_o <= PERIOD_VIDEO_DATA;
        end if;

      when ST_VIDEO_PRE =>
        if is_video_guard(pixel_s) then
          period_o <= PERIOD_VIDEO_GUARD;
        else
          period_o <= PERIOD_VIDEO_PRE;
        end if;

      when ST_VIDEO_GUARD =>
        period_o <= PERIOD_VIDEO_GUARD;

      when ST_VIDEO =>
        if is_control(de_s) then
          period_o <= PERIOD_CONTROL;
        else
          period_o <= PERIOD_VIDEO_DATA;
        end if;

      when ST_DI_PRE =>
        if is_di_guard(terc4_s, pixel_s) then
          period_o <= PERIOD_DI_GUARD;
        else
          period_o <= PERIOD_DI_PRE;
        end if;

      when ST_DI_GUARD | ST_DI_TRAIL_GUARD =>
        period_o <= PERIOD_DI_GUARD;

      when ST_DI_DATA =>
        period_o <= PERIOD_DI_DATA;

      when ST_DI_NEXT =>
        if is_di_continuation(terc4_s) then
          period_o <= PERIOD_DI_DATA;
        else
          period_o <= PERIOD_DI_GUARD;
        end if;
    end case;
  end process;

  bytes: for i in 0 to 2
  generate
    pixel_s(i) <= byte(channel_s(i));
  end generate;

  pixel_o <= pixel_s;

  -- Held across the periods that carry no sync, so what comes out is
  -- a raster's syncs rather than only the symbols that state them.
  syncs: process(r, de_s, terc4_s, control_s) is
  begin
    if carries_sync(r.state, de_s, terc4_s) then
      hsync_o <= control_s(0)(0);
      vsync_o <= control_s(0)(1);
    else
      hsync_o <= r.hsync;
      vsync_o <= r.vsync;
    end if;
  end process;

  di_hdr_o <= control_s(0)(3 downto 2);
  di_data_o <= control_s(2) & control_s(1);

end architecture;
