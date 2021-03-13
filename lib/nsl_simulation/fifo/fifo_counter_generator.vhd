library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_counter_generator is
  generic (
    width: integer
    );
  port (
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    valid_o: out std_ulogic;
    ready_i: in std_ulogic;
    data_o: out std_ulogic_vector(width-1 downto 0)
    );
end fifo_counter_generator;

architecture rtl of fifo_counter_generator is
  
  signal r_counter : std_ulogic_vector(width-1 downto 0);

begin

  reg: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if ready_i = '1' then
        r_counter <= std_ulogic_vector(unsigned(r_counter) + 1);
      end if;
    end if;
    if (reset_n_i = '0') then
      r_counter <= (others => '0');
    end if;
  end process reg;

  moore: process (clock_i)
  begin
    if falling_edge(clock_i) then
      valid_o <= reset_n_i;
      data_o <= r_counter;
    end if;
  end process;
  
  
end rtl;
