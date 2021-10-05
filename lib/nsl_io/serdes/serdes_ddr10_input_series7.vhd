library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;

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

architecture series7 of serdes_ddr10_input is

  signal cascade1, cascade2, reset_s, bit_clock_n_s : std_ulogic;
  signal d: std_ulogic_vector(0 to 9);

begin

  reset_s <= not reset_n_i;

  ltr: if left_to_right_c
  generate
    parallel_o <= d;
  end generate;

  rtl: if not left_to_right_c
  generate
    in_map: for i in 0 to 9
    generate
      parallel_o(9-i) <= d(i);
    end generate;
  end generate;

  bit_clock_n_s <= not bit_clock_i;

  master: unisim.vcomponents.iserdese2
    generic map (
      data_rate => "DDR",
      data_width => 10,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => "IFD",
      serdes_mode => "MASTER"
      )
    port map (
      q1 => d(0),
      q2 => d(1),
      q3 => d(2),
      q4 => d(3),
      q5 => d(4),
      q6 => d(5),
      q7 => d(6),
      q8 => d(7),
      shiftout1 => cascade1,
      shiftout2 => cascade2,
      bitslip => bitslip_i,
      ce1 => '1',
      ce2 => '1',
      clk => bit_clock_i,
      clkb => bit_clock_n_s,
      clkdiv => word_clock_i,
      clkdivp => '0',
      d => '0',
      ddly => serial_i,
      rst => reset_s,
      shiftin1 => '0',
      shiftin2 => '0',
      dynclkdivsel => '0',
      dynclksel => '0',
      ofb => '0',
      oclk => '0',
      oclkb => '0'
      );

  slave: unisim.vcomponents.iserdese2
    generic map (
      data_rate => "DDR",
      data_width => 10,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => "IFD",
      serdes_mode => "SLAVE"
      )
    port map (
      q3 => d(8),
      q4 => d(9),
      shiftin1 => cascade1,
      shiftin2 => cascade2,
      bitslip => bitslip_i,
      ce1 => '1',
      ce2 => '1',
      clk => bit_clock_i,
      clkb => bit_clock_n_s,
      clkdiv => word_clock_i,
      clkdivp => '0',
      d => '0',
      ddly => '0',
      rst => reset_s,
      dynclkdivsel => '0',
      dynclksel => '0',
      ofb => '0',
      oclk => '0',
      oclkb => '0'
      );

end architecture;
