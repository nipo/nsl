library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gowin;

entity serdes_ddr10_input is
  generic(
    left_to_right_c : boolean := false
    );
  port(
    bit_clock_i : in std_ulogic;
    word_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    serial_i : in std_ulogic;
    parallel_o : out std_ulogic_vector(0 to 9);

    bitslip_i : in std_ulogic
    );
end entity;

architecture gw1n of serdes_ddr10_input is

  signal reset_s, bit_clock_n_s : std_ulogic;
  signal d_s: std_ulogic_vector(0 to 9);

begin

  reset_s <= not reset_n_i;

  ltr: if left_to_right_c
  generate
    parallel_o <= d_s;
  end generate;

  rtl: if not left_to_right_c
  generate
    in_map: for i in 0 to 9
    generate
      parallel_o(9-i) <= d_s(i);
    end generate;
  end generate;

  bit_clock_n_s <= not bit_clock_i;

  inst: gowin.components.ides10
    port map (
      q0 => d_s(0),
      q1 => d_s(1),
      q2 => d_s(2),
      q3 => d_s(3),
      q4 => d_s(4),
      q5 => d_s(5),
      q6 => d_s(6),
      q7 => d_s(7),
      q8 => d_s(8),
      q9 => d_s(9),
      d => serial_i,
      fclk => bit_clock_i,
      pclk => word_clock_i,
      calib => bitslip_i,
      reset => reset_s
      );

end architecture;
