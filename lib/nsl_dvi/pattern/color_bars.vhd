library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;
use nsl_color.rgb.all;

entity color_bars is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      pixel_ready_i : in std_ulogic;
      pixel_o : out nsl_color.rgb.rgb24
    );
end color_bars;

architecture beh of color_bars is

  type regs_t is
  record
    color: unsigned(2 downto 0);
    bar_left: natural range 0 to 127;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.color <= "000";
      r.bar_left <= 0;
    end if;
  end process;

  transition: process(r, sol_i, pixel_ready_i) is
  begin
    rin <= r;

    if pixel_ready_i = '1' then
      if r.bar_left /= 0 then
        rin.bar_left <= r.bar_left - 1;
      else
        rin.bar_left <= 127;
        rin.color <= r.color + 1;
      end if;
    end if;

    if sol_i = '1' then
      rin.bar_left <= 127;
      rin.color <= "000";
    end if;
  end process;

  pixel_o <= to_rgb24(rgb3_from_suv(std_ulogic_vector(r.color)));

end beh;
