library ieee;
use ieee.std_logic_1164.all;

library sb_ice, nsl_io;

entity ice40_opendrain_io_driver is
  port(
    v_i : in nsl_io.io.opendrain;
    v_o : out std_ulogic;
    io_io : inout std_logic
    );
end entity;

architecture beh of ice40_opendrain_io_driver is
begin

  v_o <= io_io;
  driver: sb_ice.components.sb_io_od
    generic map(
      pin_type => "011001",
      neg_trigger => '0'
      )
    port map(
      packagepin => io_io,
      dout0 => v_i.drain_n,
      dout1 => v_i.drain_n,
      clockenable => '0',
      latchinputvalue => '0',
      inputclk => '0',
      outputclk => '0',
      din1 => open,
      din0 => open
      );

end architecture;
