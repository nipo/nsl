library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math;

entity dvi_colormap_lookup is
  generic(
    color_count_l2_c: natural
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    palette_i : nsl_color.rgb.rgb24_vector(0 to 2**color_count_l2_c-1);

    sof_i : in  std_ulogic;
    sol_i : in  std_ulogic;
    pixel_ready_i : in std_ulogic;
    pixel_valid_o : out std_ulogic;
    pixel_o : out nsl_color.rgb.rgb24;

    color_ready_o : out std_ulogic;
    color_valid_i : in std_ulogic := '1';
    color_i : in unsigned(color_count_l2_c-1 downto 0)
    );
end entity;

architecture beh of dvi_colormap_lookup is

  subtype color_t is unsigned(color_count_l2_c-1 downto 0);

  type state_t is (
    ST_RESET,
    ST_EMPTY,
    ST_PIPE,
    ST_FULL
    );

  type regs_t is
  record
    state : state_t;
    color: color_t;
    pixel: nsl_color.rgb.rgb24;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, palette_i, sof_i, sol_i, pixel_ready_i, color_i, color_valid_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if color_valid_i = '1' then
          rin.color <= color_i;
          rin.state <= ST_PIPE;
        end if;

      when ST_PIPE =>
        if color_valid_i = '1' and pixel_ready_i = '1' then
          rin.pixel <= palette_i(to_integer(color_i));
        elsif color_valid_i = '1' and pixel_ready_i = '0' then
          rin.color <= color_i;
          rin.state <= ST_FULL;
        elsif color_valid_i = '0' and pixel_ready_i = '0' then
          rin.state <= ST_EMPTY;
        end if;

      when ST_FULL =>
        if pixel_ready_i = '1' then
          rin.pixel <= palette_i(to_integer(r.color));
          rin.state <= ST_PIPE;
        end if;
    end case;

    if sof_i = '1' or sol_i = '1' then
      rin.state <= ST_EMPTY;
    end if;
  end process;

  moore: process(r) is
  begin
    color_ready_o <= '0';
    pixel_valid_o <= '0';
    pixel_o <= nsl_color.rgb.rgb24_green;

    case r.state is
      when ST_RESET =>
        null;

      when ST_EMPTY =>
        color_ready_o <= '1';

      when ST_PIPE =>
        color_ready_o <= '1';
        pixel_valid_o <= '1';
        pixel_o <= r.pixel;

      when ST_FULL =>
        pixel_valid_o <= '1';
        pixel_o <= r.pixel;
    end case;
  end process;

--  pixel_o <= palette_i(to_integer(color_i));
--  pixel_valid_o <= color_valid_i;
--  color_ready_o <= pixel_ready_i;

end architecture;
