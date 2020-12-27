library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_smi;
use nsl_smi.smi.all;

entity smi_slave_line_driver is
  port(
      smi_io : inout smi_bus;
      slave_o  : out smi_slave_i;
      slave_i  : in smi_slave_o
    );
end entity;

architecture beh of smi_slave_line_driver is
begin

  mdio_driver: nsl_io.io.directed_io_driver
    port map(
      v_i => slave_i.mdio,
      v_o => slave_o.mdio,
      io_io => smi_io.mdio
      );

  slave_o.mdc <= smi_io.mdc;

end architecture;
