library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;
use nsl_video.dvp.all;

entity dvp_to_pixel_stream is
  generic(
    config_c: nsl_video.pixel_stream.config_t;
    format_c: nsl_video.dvp.format_t := FORMAT_RGB565;
    geometry_c: nsl_video.mode.geometry_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    valid_i: in std_ulogic;
    sof_i: in std_ulogic;
    sol_i: in std_ulogic;
    data_i: in std_ulogic_vector(15 downto 0);

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t;

    overflow_o: out std_ulogic
    );
end entity;

architecture beh of dvp_to_pixel_stream is

  constant last_x_c: natural := geometry_c.width - 1;
  constant last_y_c: natural := geometry_c.height - 1;

  type regs_t is
  record
    -- Last pixel taken, waiting for the next word to tell whether it
    -- closes its line.  A held pixel that is done closes its frame
    -- and only waits for room in out_m.
    held: pixel_t;
    held_valid, held_sof, held_done, held_error: boolean;
    -- Position of the held pixel.  Meaningful while a held pixel is
    -- not done, which is exactly while a frame is being let through.
    x: natural range 0 to last_x_c;
    y: natural range 0 to last_y_c;

    out_m: nsl_video.pixel_stream.master_t;
    overflow: boolean;
  end record;

  signal r, rin: regs_t;

  -- Rescales a component to component_bits by repeating its bits from
  -- the most significant one, which truncates when narrowing.
  function rescaled(v: unsigned) return component_t
  is
    alias xv: unsigned(v'length-1 downto 0) is v;
    constant bits: natural := config_c.component_bits;
    variable ret: component_t := (others => '0');
  begin
    for i in 0 to bits-1
    loop
      ret(bits-1-i) := xv(xv'left - (i mod xv'length));
    end loop;
    return ret;
  end function;

  function word_pixel(word: std_ulogic_vector(15 downto 0)) return pixel_t
  is
    variable ret: pixel_t := pixel_zero_c;
  begin
    case format_c is
      when FORMAT_RGB565 =>
        if config_c.colorspace = COLORSPACE_RGB565 then
          ret(0) := unsigned(word);
          return ret;
        end if;

        ret(0) := rescaled(unsigned(word(15 downto 11)));
        ret(1) := rescaled(unsigned(word(10 downto 5)));
        ret(2) := rescaled(unsigned(word(4 downto 0)));

      when others =>
        assert false
          report "Unimplemented DVP word format"
          severity failure;
    end case;
    return ret;
  end function;

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A DVP word makes one pixel, a beat takes one pixel, "
      & "and the frame holds at least one",
      condition_c => config_c.pixel_count = 1
      and geometry_c.width /= 0
      and geometry_c.height /= 0
      )
    port map(
      unused_i => '0'
      );

  format_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Only RGB565 is implemented, into an RGB or RGB565 stream",
      condition_c => format_c = FORMAT_RGB565
      and (config_c.colorspace = COLORSPACE_RGB
           or config_c.colorspace = COLORSPACE_RGB565)
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.held_valid <= false;
      r.out_m <= transfer_defaults(config_c);
      r.overflow <= false;
    end if;
  end process;

  transition: process(r, valid_i, sof_i, sol_i, data_i, out_i) is
    variable starts_frame, starts_line, continues: boolean;
    variable out_free, pending, flush: boolean;
    variable close, advance, release, abort: boolean;
    variable close_eof, close_error: boolean;
    variable wants, slot_free, take, final: boolean;
    variable x: natural range 0 to last_x_c;
    variable y: natural range 0 to last_y_c;
  begin
    rin <= r;

    starts_frame := valid_i = '1' and sof_i = '1';
    starts_line := valid_i = '1' and (sol_i = '1' or sof_i = '1');
    continues := valid_i = '1' and not starts_line;

    out_free := not is_valid(config_c, r.out_m) or is_ready(config_c, out_i);
    pending := r.held_valid and not r.held_done;
    flush := r.held_valid and r.held_done and out_free;

    -- What the incoming word does to the pending pixel: a line start
    -- closes its line, a word further along the same line pushes it
    -- out.  A word past the line width is cropped.
    close := pending and starts_line;
    advance := pending and continues and r.x /= last_x_c;
    release := (close or advance) and out_free;
    abort := (close or advance) and not out_free;

    -- A frame starting while one is still pending cuts that one short
    close_eof := starts_frame or r.y = last_y_c;
    close_error := starts_frame or r.x /= last_x_c;

    wants := starts_frame
             or (close and r.y /= last_y_c)
             or advance;
    slot_free := not r.held_valid or flush or release;
    take := wants and slot_free;

    if starts_line then
      x := 0;
    elsif advance then
      x := r.x + 1;
    else
      x := r.x;
    end if;

    if starts_frame then
      y := 0;
    elsif close and r.y /= last_y_c then
      y := r.y + 1;
    else
      y := r.y;
    end if;

    final := x = last_x_c and y = last_y_c;

    rin.overflow <= wants and not slot_free;

    if is_taken(config_c, r.out_m, out_i) then
      rin.out_m <= transfer_defaults(config_c);
    end if;

    if flush then
      rin.out_m <= transfer(cfg => config_c,
                            pixel => r.held,
                            sof => r.held_sof,
                            last => true,
                            eof => true,
                            error => r.held_error);
    elsif release then
      rin.out_m <= transfer(cfg => config_c,
                            pixel => r.held,
                            sof => r.held_sof,
                            last => close,
                            eof => close and close_eof,
                            error => close and close_error);
    end if;

    if flush or release then
      rin.held_valid <= false;
    end if;

    -- Nowhere to put the pending pixel: it closes the frame as soon
    -- as it can leave, and the rest of the frame is dropped.
    if abort then
      rin.held_done <= true;
      rin.held_error <= true;
    end if;

    if take then
      rin.held <= word_pixel(data_i);
      rin.held_valid <= true;
      rin.held_sof <= starts_frame;
      rin.held_done <= final;
      rin.held_error <= false;
      rin.x <= x;
      rin.y <= y;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= r.out_m;
    overflow_o <= '0';
    if r.overflow then
      overflow_o <= '1';
    end if;
  end process;

end architecture;
