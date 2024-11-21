library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package spi is

  type spi_bus is record
    mosi : std_logic;
    miso : std_logic;
    sck  : std_logic;
    cs_n : std_logic;
  end record;

  type spi_slave_i is record
    mosi : std_ulogic;
    sck  : std_ulogic;
    cs_n : std_ulogic;
  end record;
  
  type spi_slave_o is record
    miso : nsl_io.io.tristated;
  end record;

  constant spi_slave_idle_c : spi_slave_o := (
    miso => nsl_io.io.tristated_z
    );

  type spi_slave_io is
  record
    o: spi_slave_o;
    i: spi_slave_i;
  end record;    

  type spi_master_o is record
    mosi : nsl_io.io.tristated;
    sck  : std_ulogic;
    cs_n : nsl_io.io.opendrain;
  end record;

  constant spi_master_idle_c : spi_master_o := (
    sck => '-',
    cs_n => nsl_io.io.opendrain_z,
    mosi => nsl_io.io.tristated_z
    );

  type spi_master_i is record
    miso : std_ulogic;
  end record;

  type spi_master_io is
  record
    o: spi_master_o;
    i: spi_master_i;
  end record;    

  type spi_slave_i_vector is array (integer range <>) of spi_slave_i;
  type spi_slave_o_vector is array (integer range <>) of spi_slave_o;
  type spi_master_i_vector is array (integer range <>) of spi_master_i;
  type spi_master_o_vector is array (integer range <>) of spi_master_o;

  function to_slave(m: spi_master_o) return spi_slave_i;
  function to_master(s: spi_slave_o) return spi_master_i;
  
end package spi;

package body spi is

  function to_slave(m: spi_master_o) return spi_slave_i
  is
  begin
    return (
      mosi => m.mosi.v,
      sck => m.sck,
      cs_n => m.cs_n.drain_n
      );
  end function;

  function to_master(s: spi_slave_o) return spi_master_i
  is
  begin
    return (
      miso => s.miso.v
      );
  end function;

end package body;
