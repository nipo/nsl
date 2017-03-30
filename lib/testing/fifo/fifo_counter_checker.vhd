library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_counter_checker is
  generic (
    width: integer
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_full_n: out std_ulogic;
    p_write: in std_ulogic;
    p_data: in std_ulogic_vector(width-1 downto 0)
    );
end fifo_counter_checker;

architecture rtl of fifo_counter_checker is
  
  signal r_last : std_ulogic_vector(width-1 downto 0);
  signal s_next : std_ulogic_vector(width-1 downto 0);

begin

  s_next <= std_ulogic_vector(unsigned(r_last) + 1);
  
  reg: process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      r_last <= (others => '1');
    elsif rising_edge(p_clk) then
      if p_write = '1' then
        if s_next /= p_data then
          report "Discontinuity in fifo stream, got " & integer'image(to_integer(unsigned(p_data))) & ", expected " & integer'image(to_integer(unsigned(s_next)));
        end if;
        r_last <= p_data;
      end if;
    end if;
  end process reg;

  p_full_n <= '1';
  
end rtl;
