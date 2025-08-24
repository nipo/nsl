library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_smi;
use nsl_smi.smi.all;

entity smi_slave_line_driver is
  port(
      mdc_i : in std_logic;
      mdio_io : inout std_logic;
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
      io_io => mdio_io
      );

  slave_o.mdc <= mdc_i;

end architecture;
