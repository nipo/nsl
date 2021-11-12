library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lut1 is
  generic (
    contents_c : std_ulogic_vector
    );
  port (
    data_i : in std_ulogic_vector;
    data_o : out std_ulogic
    );
begin

  assert
    contents_c'length = 2 ** data_i'length
    report "Initialization vector does not match truth table size"
    severity failure;

end entity;

architecture beh of lut_1p is

  signal idx: unsigned(data_i'length-1 downto 0);

begin

  idx <= unsigned(data_i);
  data_o <= contents_c(to_integer(idx));
  
end architecture;
