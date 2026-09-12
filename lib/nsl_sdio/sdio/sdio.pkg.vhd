library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

-- Wires of an SD, SDIO or MMC bus, as seen from either end.
--
-- A bus carries one clock driven by the host, one bidirectional
-- command line and up to eight bidirectional data lines.  How many
-- data lines are in use is a runtime property, not a wiring one: a
-- card is identified on DAT0 alone and only switched to a wider bus
-- afterwards.
package sdio is

  -- Data lines a bus can have.  SD sockets wire four of them, MMC
  -- parts up to eight.  A design with fewer leaves the upper ones
  -- unconnected and they vanish at elaboration.
  constant max_lane_count_c: natural := 8;

  subtype lane_count_t is integer range 1 to max_lane_count_c;

  -- Data lines a transfer spreads over.  Only these three widths
  -- exist: SD cards do 1 and 4, MMC parts add 8.
  type bus_width_t is (
    SDIO_WIDTH_1,
    SDIO_WIDTH_4,
    SDIO_WIDTH_8
    );

  function lane_count(width: bus_width_t) return lane_count_t;

  type sdio_slave_i is
  record
    clk: std_ulogic;
    cmd: std_ulogic;
    d: std_ulogic_vector(max_lane_count_c - 1 downto 0);
  end record;

  type sdio_slave_o is
  record
    cmd: nsl_io.io.tristated;
    d: nsl_io.io.tristated_vector(max_lane_count_c - 1 downto 0);
  end record;

  constant sdio_slave_idle_c: sdio_slave_o := (
    cmd => nsl_io.io.tristated_z,
    d => (others => nsl_io.io.tristated_z)
    );

  type sdio_slave_io is
  record
    o: sdio_slave_o;
    i: sdio_slave_i;
  end record;

  type sdio_master_o is
  record
    clk: std_ulogic;
    cmd: nsl_io.io.tristated;
    d: nsl_io.io.tristated_vector(max_lane_count_c - 1 downto 0);
  end record;

  constant sdio_master_idle_c: sdio_master_o := (
    clk => '0',
    cmd => nsl_io.io.tristated_z,
    d => (others => nsl_io.io.tristated_z)
    );

  type sdio_master_i is
  record
    cmd: std_ulogic;
    d: std_ulogic_vector(max_lane_count_c - 1 downto 0);
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

  -- Lumped view of the wires, either as a top-level inout port group,
  -- or to resolve both ends of a bus against each other in a
  -- testbench.  Both ends drive their view of it and read the result
  -- back.
  type sdio_bus is
  record
    clk: std_logic;
    cmd: std_logic;
    d: std_logic_vector(max_lane_count_c - 1 downto 0);
  end record;

  -- What the wires settle to when no end drives them.  The command
  -- and data lines are pulled up, so a testbench has to drive this as
  -- a third, weak end of the bus for released lines to read as ones.
  constant sdio_bus_released_c: sdio_bus := (
    clk => 'Z',
    cmd => 'H',
    d => (others => 'H')
    );

  function to_bus(m: sdio_master_o) return sdio_bus;
  function to_bus(s: sdio_slave_o) return sdio_bus;
  function to_master_i(b: sdio_bus) return sdio_master_i;
  function to_slave_i(b: sdio_bus) return sdio_slave_i;

end package sdio;

package body sdio is

  function lane_count(width: bus_width_t) return lane_count_t
  is
  begin
    case width is
      when SDIO_WIDTH_1 => return 1;
      when SDIO_WIDTH_4 => return 4;
      when SDIO_WIDTH_8 => return 8;
    end case;
  end function;

  function to_bus(m: sdio_master_o) return sdio_bus
  is
    variable ret: sdio_bus;
  begin
    ret.clk := m.clk;
    ret.cmd := nsl_io.io.to_logic(m.cmd);
    for i in ret.d'range
    loop
      ret.d(i) := nsl_io.io.to_logic(m.d(i));
    end loop;

    return ret;
  end function;

  function to_bus(s: sdio_slave_o) return sdio_bus
  is
    variable ret: sdio_bus;
  begin
    ret.clk := 'Z';
    ret.cmd := nsl_io.io.to_logic(s.cmd);
    for i in ret.d'range
    loop
      ret.d(i) := nsl_io.io.to_logic(s.d(i));
    end loop;

    return ret;
  end function;

  function to_master_i(b: sdio_bus) return sdio_master_i
  is
    variable ret: sdio_master_i;
  begin
    ret.cmd := to_x01(b.cmd);
    ret.d := std_ulogic_vector(to_x01(b.d));

    return ret;
  end function;

  function to_slave_i(b: sdio_bus) return sdio_slave_i
  is
    variable ret: sdio_slave_i;
  begin
    ret.clk := to_x01(b.clk);
    ret.cmd := to_x01(b.cmd);
    ret.d := std_ulogic_vector(to_x01(b.d));

    return ret;
  end function;

end package body;
