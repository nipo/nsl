library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_counter_generator is
  generic (
    width: integer
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_valid: out std_ulogic;
    p_ready: in std_ulogic;
    p_data: out std_ulogic_vector(width-1 downto 0)
    );
end fifo_counter_generator;

architecture rtl of fifo_counter_generator is
  
  signal r_counter : std_ulogic_vector(width-1 downto 0);

begin

  reg: process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r_counter <= (others => '0');
    elsif rising_edge(p_clk) then
      if p_ready = '1' then
        r_counter <= std_ulogic_vector(unsigned(r_counter) + 1);
      end if;
    end if;
  end process reg;

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_valid <= p_resetn;
      p_data <= r_counter;
    end if;
  end process;
  
  
end rtl;
