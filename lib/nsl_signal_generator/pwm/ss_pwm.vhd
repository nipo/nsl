library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ss_pwm is
  port (
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    pwm_o    : out std_ulogic;

    duty_i : in unsigned(7 downto 0)
    );
end entity;

architecture beh of ss_pwm is

  signal counter_s : unsigned(7 downto 0);

begin

  bla: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      counter_s <= to_unsigned(0, 8);
    elsif rising_edge(clock_i) then
      if counter_s = x"fe" then
        counter_s <= to_unsigned(0, 8);
      else
        counter_s <= counter_s + 1;
      end if;
    end if;
  end process;

  pwm_o <= '1' when counter_s < duty_i else '0';

end architecture;
