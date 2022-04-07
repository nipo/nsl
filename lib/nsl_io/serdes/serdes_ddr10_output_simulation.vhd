library ieee;
use ieee.std_logic_1164.all;

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

architecture simulation of serdes_ddr10_output is

  signal d: std_ulogic_vector(0 to 9);
  signal shreg: std_ulogic_vector(0 to 9);
  signal on_fall: std_ulogic;
  signal ctr: integer range 0 to 4;

begin

  d_take: process(word_clock_i) is
  begin
    if rising_edge(word_clock_i) then
      if left_to_right_c then
        d <= parallel_i;
      else
        for i in 0 to 9
        loop
          d(9-i) <= parallel_i(i);
        end loop;
      end if;
    end if;
  end process;

  shift: process(bit_clock_i, reset_n_i) is
  begin
    if rising_edge(bit_clock_i) then
      on_fall <= shreg(1);
      serial_o <= shreg(0);
      shreg <= shreg(2 to 9) & "--";
      if ctr = 0 then
        ctr <= 4;
        shreg <= d;
      else
        ctr <= ctr - 1;
      end if;
    end if;

    if falling_edge(bit_clock_i) then
      serial_o <= on_fall;
    end if;

    if reset_n_i = '0' then
      ctr <= 0;
    end if;
  end process;

end architecture;
