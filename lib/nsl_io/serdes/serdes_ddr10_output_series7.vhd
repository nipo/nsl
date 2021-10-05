library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity serdes_ddr10_output is
  generic(
    left_to_right_c : boolean := false
    );
  port(
    bit_clock_i : in std_ulogic;
    word_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    parallel_i : in std_ulogic_vector(0 to 9);
    serial_o : out std_ulogic
    );
end entity;

architecture series7 of serdes_ddr10_output is

  signal cascade1, cascade2, reset : std_ulogic;
  signal d: std_ulogic_vector(0 to 9);

begin

  reset <= not reset_n_i;

  ltr: if left_to_right_c
  generate
    d <= parallel_i;
  end generate;

  rtl: if not left_to_right_c
  generate
    in_map: for i in 0 to 9
    generate
      d(9-i) <= parallel_i(i);
    end generate;
  end generate;


  master: unisim.vcomponents.oserdese2
    generic map(
      data_rate_oq => "DDR",
      data_rate_tq => "SDR",
      data_width => 10,
      serdes_mode => "MASTER",
      tristate_width => 1
      )
    port map(
      oq => serial_o,
      clk => bit_clock_i,
      clkdiv => word_clock_i,
      d1 => d(0),
      d2 => d(1),
      d3 => d(2),
      d4 => d(3),
      d5 => d(4),
      d6 => d(5),
      d7 => d(6),
      d8 => d(7),
      tce => '0',
      oce => '1',
      tbytein => '0',
      rst => reset,
      shiftin1 => cascade1,
      shiftin2 => cascade2,
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0'
      );

  slave: unisim.vcomponents.oserdese2
    generic map(
      data_rate_oq => "DDR",
      data_rate_tq => "SDR",
      data_width => 10,
      serdes_mode => "SLAVE",
      tristate_width => 1
      )
    port map (
      shiftout1 => cascade1,
      shiftout2 => cascade2,
      clk => bit_clock_i,
      clkdiv => word_clock_i,
      d1 => '0',
      d2 => '0',
      d3 => d(8),
      d4 => d(9),
      d5 => '0',
      d6 => '0',
      d7 => '0',
      d8 => '0',
      tce => '0',
      oce => '1',
      tbytein => '0',
      rst => reset,
      shiftin1 => '0',
      shiftin2 => '0',
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0'
      );

end architecture;
