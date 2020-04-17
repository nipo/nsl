library ieee;
use ieee.std_logic_1164.all;

entity async_edge is
  generic(
    cycle_count_c : natural range 2 to 8 := 2;
    target_value_c : std_ulogic := '1';
    async_reset_c : boolean := true
    );
  port(
    clock_i : in  std_ulogic;
    data_i  : in  std_ulogic;
    data_o  : out std_ulogic
    );

end async_edge;

architecture rtl of async_edge is

  attribute keep : string;
  signal tig_reg_d : std_ulogic_vector(0 to cycle_count_c-1);
  attribute keep of tig_reg_d : signal is "TRUE";
  constant opposed_value_c : std_ulogic := not target_value_c;

begin

  forward: process (clock_i, data_i)
  begin
    if async_reset_c and data_i = opposed_value_c then
      tig_reg_d <= (others => opposed_value_c);
    elsif rising_edge(clock_i) then
      if not async_reset_c and data_i = opposed_value_c then
        tig_reg_d <= (others => opposed_value_c);
      else
        tig_reg_d <= tig_reg_d(tig_reg_d'left + 1 to tig_reg_d'right) & target_value_c;
      end if;
    end if;
  end process;

  data_o <= tig_reg_d(tig_reg_d'left);
  
end rtl;
