library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_counter_checker is
  generic (
    width: integer
    );
  port (
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    read_o: out std_ulogic;
    valid_i: in std_ulogic;
    data_i: in std_ulogic_vector(width-1 downto 0)
    );
end fifo_counter_checker;

architecture rtl of fifo_counter_checker is
  
  signal r_last : std_ulogic_vector(width-1 downto 0);
  signal s_next : std_ulogic_vector(width-1 downto 0);

begin

  s_next <= std_ulogic_vector(unsigned(r_last) + 1);
  
  reg: process (clock_i, reset_n_i)
  begin
    if (reset_n_i = '0') then
      r_last <= (others => '1');
    elsif rising_edge(clock_i) then
      if valid_i = '1' then
        if s_next /= data_i then
          report "Discontinuity in fifo stream, got " & integer'image(to_integer(unsigned(data_i))) & ", expected " & integer'image(to_integer(unsigned(s_next)));
        end if;
        r_last <= data_i;
      end if;
    end if;
  end process reg;

  read_o <= '1';
  
end rtl;
