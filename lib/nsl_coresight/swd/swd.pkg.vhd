library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

-- SWD bus abstracted types.
package swd is

  type swd_master_o is record
    dio : nsl_io.io.directed;
    clk : std_ulogic;
  end record;

  type swd_master_i is record
    dio : std_ulogic;
  end record;

  type swd_master_bus is
  record
    o: swd_master_o;
    i: swd_master_i;
  end record;
  
  type swd_slave_o is record
    dio : nsl_io.io.directed;
  end record;

  type swd_slave_i is record
    clk : std_ulogic;
    dio : std_ulogic;
  end record;

  type swd_slave_bus is
  record
    o: swd_slave_o;
    i: swd_slave_i;
  end record;

  type swd_master_o_vector is array (integer range <>) of swd_master_o;
  type swd_master_i_vector is array (integer range <>) of swd_master_i;
  type swd_master_bus_vector is array (integer range <>) of swd_master_bus;
  
  type swd_slave_o_vector is array (integer range <>) of swd_slave_o;
  type swd_slave_i_vector is array (integer range <>) of swd_slave_i;
  type swd_slave_bus_vector is array (integer range <>) of swd_slave_bus;
  
  component swd_master_driver is
    port(
      swd_i: in swd_master_o;
      swd_o: out swd_master_i;
      swdio_io: inout std_logic;
      swclk_o: out std_ulogic
      );
  end component;
  
  component swd_slave_driver is
    generic(
      clock_buffer_mode_c: string := "global"
      );
    port(
      swd_i: in swd_slave_o;
      swd_o: out swd_slave_i;
      swdio_io: inout std_logic;
      swclk_i: in std_ulogic
      );
  end component;

  function to_master(s: swd_slave_o) return swd_master_i;
  function to_slave(m: swd_master_o) return swd_slave_i;
  
end package swd;

package body swd is

  function to_master(s: swd_slave_o) return swd_master_i
  is
  begin
    return swd_master_i'(
      dio => s.dio.v
      );
  end function;

  function to_slave(m: swd_master_o) return swd_slave_i
  is
  begin
    return swd_slave_i'(
      clk => m.clk,
      dio => m.dio.v
      );
  end function;

end package body;
