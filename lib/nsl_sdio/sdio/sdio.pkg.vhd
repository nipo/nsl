library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package sdio is

  type sdio_bus is record
    clk : std_logic;
    cmd : std_logic;
    d   : std_logic_vector(3 downto 0);
  end record;

  type sdio_slave_i is record
    clk : std_ulogic;
    cmd : std_ulogic;
    d   : std_ulogic_vector(3 downto 0);
  end record;
  
  type sdio_slave_o is record
    cmd : nsl_io.io.tristated;
    d   : nsl_io.io.tristated_vector(3 downto 0);
  end record;

  constant sdio_slave_idle_c : sdio_slave_o := (
    cmd => nsl_io.io.tristated_z,
    d => (others => nsl_io.io.tristated_z)
    );

  type sdio_slave_io is
  record
    o: sdio_slave_o;
    i: sdio_slave_i;
  end record;    

  type sdio_master_o is record
    clk : std_ulogic;
    cmd : nsl_io.io.tristated;
    d   : nsl_io.io.tristated_vector(3 downto 0);
  end record;

  constant sdio_master_idle_c : sdio_master_o := (
    clk => '0',
    cmd => nsl_io.io.tristated_z,
    d => (others => nsl_io.io.tristated_z)
    );

  type sdio_master_i is record
    cmd : std_ulogic;
    d   : std_ulogic_vector(3 downto 0);
  end record;

  type sdio_master_io is
  record
    o: sdio_master_o;
    i: sdio_master_i;
  end record;    

  type sdio_slave_i_vector is array (integer range <>) of sdio_slave_i;
  type sdio_slave_o_vector is array (integer range <>) of sdio_slave_o;
  type sdio_master_i_vector is array (integer range <>) of sdio_master_i;
  type sdio_master_o_vector is array (integer range <>) of sdio_master_o;

  function to_slave(m: sdio_master_o) return sdio_slave_i;
  function to_master(s: sdio_slave_o) return sdio_master_i;
  
end package sdio;

package body sdio is

  function to_slave(m: sdio_master_o) return sdio_slave_i
  is
  begin
    return (
      clk => m.clk,
      cmd => m.cmd.v,
      d => (m.d(3).v, m.d(2).v, m.d(1).v, m.d(0).v)
      );
  end function;

  function to_master(s: sdio_slave_o) return sdio_master_i
  is
  begin
    return (
      cmd => s.cmd.v,
      d => (s.d(3).v, s.d(2).v, s.d(1).v, s.d(0).v)
      );
  end function;

end package body;
