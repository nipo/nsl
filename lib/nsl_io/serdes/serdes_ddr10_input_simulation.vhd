library ieee;
use ieee.std_logic_1164.all;

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

architecture simulation of serdes_ddr10_input is

  signal d, shreg: std_ulogic_vector(0 to 9);
  signal bitslip: boolean;
  signal ctr, shift_count: integer range 0 to 10;

begin

  d_present: process(word_clock_i, reset_n_i) is
  begin
    if rising_edge(word_clock_i) then
      bitslip <= bitslip_i = '1';
      if bitslip_i = '1' then
        if shift_count = 9 then
          shift_count <= 0;
        else
          shift_count <= shift_count + 1;
        end if;
      end if;
      
      if left_to_right_c then
        parallel_o <= d;
      else
        for i in 0 to 9
        loop
          parallel_o(9-i) <= d(i);
        end loop;
      end if;
    end if;

    if reset_n_i = '0' then
      shift_count <= 4;
    end if;
  end process;

  ingress: process(bit_clock_i, reset_n_i) is
  begin
    if rising_edge(bit_clock_i) or falling_edge(bit_clock_i) then
      shreg <= shreg(1 to 9) & serial_i;
      if ctr /= 0 then
        ctr <= ctr - 1;
      else
        d <= shreg;
        if bitslip then
          ctr <= 10;
        else
          ctr <= 9;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      ctr <= 0;
    end if;
  end process;

  mark_o <= '1' when shift_count = 0 else '0';
  
end architecture;
