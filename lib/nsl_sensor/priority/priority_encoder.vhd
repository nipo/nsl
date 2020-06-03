library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_sensor;
use nsl_sensor.priority.active_lowest_index;

entity priority_encoder is
  generic (
    count_c : positive
    );
  port (
    data_i : in std_ulogic_vector(0 to count_c - 1);
    lowest_o : out unsigned(nsl_math.arith.log2(count_c-1)-1 downto 0);
    active_o : out std_ulogic
    );
end entity;

architecture beh of priority_encoder is
begin

  lowest_o <= to_unsigned(active_lowest_index(data_i), lowest_o'length)
              when data_i /= (data_i'range => '0') else (others => '-');
  active_o <= '1' when data_i /= (data_i'range => '0') else '0';

end architecture;

