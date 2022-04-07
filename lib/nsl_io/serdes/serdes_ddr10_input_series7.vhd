library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim, nsl_data;

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

    bitslip_i : in std_ulogic;
    mark_o : out std_ulogic
    );
end entity;

architecture series7 of serdes_ddr10_input is

  constant from_delay_c: boolean := true;
  constant iobdelay_c: string := nsl_data.text.if_else(from_delay_c, "BOTH", "NONE");
  signal cascade1, cascade2, reset_s, bit_clock_n_s : std_ulogic;
  signal d: std_ulogic_vector(0 to 9);
  signal slip_count: integer range 0 to 9;
  signal d_i, ddly_i: std_ulogic;

begin

  reset_s <= not reset_n_i;

  is_from_delay: if from_delay_c
  generate
    d_i <= '0';
    ddly_i <= serial_i;
  end generate;
  
  is_from_pin: if not from_delay_c
  generate
    d_i <= serial_i;
    ddly_i <= '0';
  end generate;
  
  output: process(d) is
  begin
    if not left_to_right_c then
      parallel_o <= d;
    else
      for i in 0 to 9
      loop
        parallel_o(9-i) <= d(i);
      end loop;
    end if;
  end process;

  bit_clock_n_s <= not bit_clock_i;

  slip_tracker: process(word_clock_i, reset_n_i) is
  begin
    if rising_edge(word_clock_i) then
      if bitslip_i = '1' then
        if slip_count = 0 then
          slip_count <= 9;
        else
          slip_count <= slip_count - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      slip_count <= 9;
    end if;
  end process;

  mark_o <= '1' when slip_count = 0 else '0';
  
  master: unisim.vcomponents.iserdese2
    generic map (
      data_rate => "DDR",
      data_width => 10,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => iobdelay_c,
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
      d => d_i,
      ddly => ddly_i,
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
      iobdelay => iobdelay_c,
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
