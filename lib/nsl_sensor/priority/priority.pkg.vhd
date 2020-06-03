library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

package priority is

  function active_lowest_index(data : std_ulogic_vector;
                               default : integer := 0)
    return integer;
  
  component priority_encoder
    generic (
      count_c : positive
      );
    port (
      data_i : in std_ulogic_vector(0 to count_c - 1);
      lowest_o : out unsigned(nsl_math.arith.log2(count_c-1)-1 downto 0);
      active_o : out std_ulogic
      );
  end component;

end package priority;

package body priority is

  function active_lowest_index(data : std_ulogic_vector;
                               default : integer := 0)
    return integer
  is
  begin
    for i in data'low to data'high
    loop
      if data(i) = '1' then
        return i;
      end if;
    end loop;
    return default;
  end function;

end package body;
