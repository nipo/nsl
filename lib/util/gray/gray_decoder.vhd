library ieee;
use ieee.std_logic_1164.all;

entity gray_decoder is
  generic(
    data_width : integer
    );
  port(
    p_gray : in std_ulogic_vector(data_width-1 downto 0);
    p_binary : out std_ulogic_vector(data_width-1 downto 0)
    );
end entity;

architecture rtl of gray_decoder is

  function xor_reduct(slv : in std_ulogic_vector) return std_logic is
    variable ret : std_logic := '0';
  begin
    for i in slv'range loop
      ret := ret xor slv(i);
    end loop;
    return ret;
  end function;

  attribute register_balancing: string;
  attribute register_balancing of p_binary: signal is "yes";
  
begin

  g: for i in 0 to data_width-1 generate
  begin
    p_binary(i) <= xor_reduct(p_gray(data_width-1 downto i));
  end generate;
  
end architecture;
