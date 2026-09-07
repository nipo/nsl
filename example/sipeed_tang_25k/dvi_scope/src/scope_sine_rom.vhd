library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- One period of a sine wave scaled to amplitude_c, synchronous read.
entity scope_sine_rom is
  generic(
    address_width_c : natural;
    value_width_c : natural;
    amplitude_c : natural
    );
  port(
    clock_i : in std_ulogic;

    address_i : in unsigned(address_width_c-1 downto 0);
    value_o : out signed(value_width_c-1 downto 0)
    );
end entity;

architecture beh of scope_sine_rom is

  type table_t is array(0 to 2**address_width_c-1) of signed(value_width_c-1 downto 0);

  function table_precalc return table_t is
    variable angle : real;
    variable ret : table_t;
  begin
    for i in ret'range
    loop
      angle := math_2_pi * real(i) / real(2**address_width_c);
      ret(i) := to_signed(integer(round(sin(angle) * real(amplitude_c))),
                          value_width_c);
    end loop;
    return ret;
  end function;

  constant table_c : table_t := table_precalc;

begin

  reader: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      value_o <= table_c(to_integer(address_i));
    end if;
  end process;

end architecture;
