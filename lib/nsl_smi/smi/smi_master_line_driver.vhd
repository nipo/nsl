library ieee;
use ieee.std_logic_1164.all;

library nsl_io, nsl_smi;
use nsl_smi.smi.all;

entity smi_master_line_driver is
  port(
      smi_io : inout smi_bus;
      master_o  : out smi_master_i;
      master_i  : in smi_master_o
    );
end entity;

architecture beh of smi_master_line_driver is
begin

  mdio_driver: nsl_io.io.directed_io_driver
    port map(
      v_i => master_i.mdio,
      v_o => master_o.mdio,
      io_io => smi_io.mdio
      );

  smi_io.mdc <= master_i.mdc;

end architecture;
