library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity rgb565_unpacker is
  generic(
    in_config_c : nsl_video.pixel_stream.config_t;
    out_config_c : nsl_video.pixel_stream.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in nsl_video.pixel_stream.master_t;
    in_o : out nsl_video.pixel_stream.slave_t;

    out_o : out nsl_video.pixel_stream.master_t;
    out_i : in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of rgb565_unpacker is

  type beat_t is
  record
    pixel: pixel_t;
    sof, last, eof, error: boolean;
  end record;

  type state_t is (
    ST_RESET,
    -- Nothing to hand out.
    ST_EMPTY,
    -- A beat is on offer, and the input may be taken behind it.
    ST_PIPE,
    -- A beat is on offer and another one waits behind it.
    ST_FULL
    );

  type regs_t is
  record
    state: state_t;
    head, tail: beat_t;
  end record;

  signal r, rin: regs_t;

  -- Rescales a component to the output width by repeating its bits
  -- from the most significant one, which truncates when narrowing.
  function rescaled(v: unsigned) return component_t
  is
    alias xv: unsigned(v'length-1 downto 0) is v;
    constant bits: natural := out_config_c.component_bits;
    variable ret: component_t := (others => '0');
  begin
    for i in 0 to bits-1
    loop
      ret(bits-1-i) := xv(xv'left - (i mod xv'length));
    end loop;
    return ret;
  end function;

  function unpacked(m: master_t) return beat_t
  is
    variable packed: component_t;
    variable ret: beat_t;
  begin
    packed := pixel(in_config_c, m)(0);
    ret.pixel := pixel_zero_c;
    ret.pixel(0) := rescaled(packed(15 downto 11));
    ret.pixel(1) := rescaled(packed(10 downto 5));
    ret.pixel(2) := rescaled(packed(4 downto 0));
    ret.sof := is_sof(in_config_c, m);
    ret.last := is_last(in_config_c, m);
    ret.eof := is_eof(in_config_c, m);
    ret.error := is_error(in_config_c, m);
    return ret;
  end function;

begin

  config_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "RGB565 unpacker takes one RGB565 pixel a beat "
      & "and makes one RGB pixel a beat",
      condition_c => in_config_c.colorspace = COLORSPACE_RGB565
      and out_config_c.colorspace = COLORSPACE_RGB
      and in_config_c.pixel_count = 1
      and out_config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable valid, ready: boolean;
    variable beat: beat_t;
  begin
    rin <= r;

    valid := is_valid(in_config_c, in_i);
    ready := is_ready(out_config_c, out_i);
    beat := unpacked(in_i);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if valid then
          rin.head <= beat;
          rin.state <= ST_PIPE;
        end if;

      when ST_PIPE =>
        if ready then
          if valid then
            rin.head <= beat;
          else
            rin.state <= ST_EMPTY;
          end if;
        elsif valid then
          rin.tail <= beat;
          rin.state <= ST_FULL;
        end if;

      when ST_FULL =>
        if ready then
          rin.head <= r.tail;
          rin.state <= ST_PIPE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(in_config_c, ready => r.state = ST_EMPTY or r.state = ST_PIPE);
    out_o <= transfer(cfg => out_config_c,
                      pixel => pixel_dontcare_c,
                      valid => false);

    if r.state = ST_PIPE or r.state = ST_FULL then
      out_o <= transfer(cfg => out_config_c,
                        pixel => r.head.pixel,
                        valid => true,
                        sof => r.head.sof,
                        last => r.head.last,
                        eof => r.head.eof,
                        error => r.head.error);
    end if;
  end process;

end architecture;
