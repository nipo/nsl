library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps_gpio_adapter is
  generic(
    io_count : positive
    );
  port(
    ps_gpio_o: in std_logic_vector(io_count-1 downto 0);
    ps_gpio_i: out std_logic_vector(io_count-1 downto 0);
    ps_gpio_t: in std_logic_vector(io_count-1 downto 0);

    tristated_o: out std_logic_vector(io_count-1 downto 0);
    tristated_oe: out std_logic_vector(io_count-1 downto 0);
    tristated_i: in std_logic_vector(io_count-1 downto 0)
    );
end entity;

architecture rtl of ps_gpio_adapter is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

--  attribute X_INTERFACE_MODE of ps_gpio_i : signal is "SLAVE";
--  attribute X_INTERFACE_INFO of ps_gpio_o : signal is "xilinx.com:interface:gpio:1.0 ps_gpio TRI_O";
--  attribute X_INTERFACE_INFO of ps_gpio_i : signal is "xilinx.com:interface:gpio:1.0 ps_gpio TRI_I";
--  attribute X_INTERFACE_INFO of ps_gpio_t : signal is "xilinx.com:interface:gpio:1.0 ps_gpio TRI_T";

  attribute X_INTERFACE_INFO of tristated_i : signal is "nsl:io:tristated:1.0 tristated i";
  attribute X_INTERFACE_INFO of tristated_o : signal is "nsl:io:tristated:1.0 tristated o";
  attribute X_INTERFACE_INFO of tristated_oe: signal is "nsl:io:tristated:1.0 tristated oe";

begin

  tristated_o <= ps_gpio_o;
  tristated_oe <= not ps_gpio_t;
  ps_gpio_i <= tristated_i;

end;
