library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

package smi is

  type smi_master_o is record
    mdio : nsl_io.io.directed;
    mdc  : std_ulogic;
  end record;

  type smi_master_i is record
    mdio : std_ulogic;
  end record;
  
  type smi_slave_o is record
    mdio : nsl_io.io.directed;
  end record;

  type smi_slave_i is record
    mdc  : std_ulogic;
    mdio : std_ulogic;
  end record;

  type smi_bus is record
    mdc  : std_logic;
    mdio : std_logic;
  end record;
  
  component smi_master_line_driver is
    port(
      smi_io : inout smi_bus;
      master_o  : out smi_master_i;
      master_i  : in smi_master_o
      );
  end component;
  
  component smi_smave_line_driver is
    port(
      smi_io : inout smi_bus;
      slave_o  : out smi_slave_i;
      slave_i  : in smi_slave_o
      );
  end component;
    
end package smi;
