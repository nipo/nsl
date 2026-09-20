library ieee;
use ieee.std_logic_1164.all;
library nsl_io;

package qspi is

  type qspi_master_o is
  record
    cs_n: std_ulogic;
    sck: std_ulogic;
    dq: nsl_io.io.tristated_vector(3 downto 0);
  end record;

  type qspi_master_i is
  record
    dq: std_ulogic_vector(3 downto 0);
  end record;

  type qspi_slave_i is
  record
    cs_n: std_ulogic;
    sck: std_ulogic;
    dq: std_ulogic_vector(3 downto 0);
  end record;

  type qspi_slave_o is
  record
    dq: nsl_io.io.tristated_vector(3 downto 0);
  end record;

  constant qspi_master_idle_c: qspi_master_o := (
    cs_n => '1',
    sck => '0',
    dq => (others => nsl_io.io.tristated_z)
    );

  constant qspi_slave_idle_c: qspi_slave_o := (
    dq => (others => nsl_io.io.tristated_z)
    );

end package;
