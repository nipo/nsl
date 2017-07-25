library ieee;
use ieee.std_logic_1164.all;

entity gray_encoder is
  generic(
    data_width : integer
    );
  port(
    p_binary : in std_ulogic_vector(data_width-1 downto 0);
    p_gray : out std_ulogic_vector(data_width-1 downto 0)
    );
end entity;

architecture rtl of gray_encoder is

begin

  p_gray <= p_binary xor ('0' & p_binary(data_width - 1 downto 1));
  
end architecture;
