library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Coresight DAP-Bus implemetation.
package dapbus is

  type dapbus_m_o is record
    sel : std_ulogic;
    enable : std_ulogic;
    write : std_ulogic;
    addr : std_ulogic_vector(15 downto 2);
    wdata : std_ulogic_vector(31 downto 0);
    abort : std_ulogic;
  end record;

  constant dapbus_m_o_idle : dapbus_m_o := (
    sel => '0',
    enable => '0',
    write => '0',
    addr => (others => '-'),
    wdata => (others => '-'),
    abort => '-'
    );

  type dapbus_m_i is record
    ready : std_ulogic;
    rdata : std_ulogic_vector(31 downto 0);
    slverr : std_ulogic;
  end record;

  constant dapbus_m_i_idle : dapbus_m_i := (
    ready => '0',
    rdata => (others => '-'),
    slverr => '-'
    );

  type dapbus_bus is
  record
    ms : dapbus_m_o;
    sm : dapbus_m_i;
  end record;
  
  type dapbus_m_o_vector is array (natural range <>) of dapbus_m_o;
  type dapbus_m_i_vector is array (natural range <>) of dapbus_m_i;

  component dapbus_interconnect is
    generic(
      access_port_count : natural range 1 to 256
      );
    port(
      s_i : in dapbus_m_o;
      s_o : out dapbus_m_i;

      m_o : out dapbus_m_o_vector(0 to access_port_count-1);
      m_i : in dapbus_m_i_vector(0 to access_port_count-1)
      );
  end component;

  component dapbus_m_o_sync is
    port(
      clock_i : in std_ulogic;

      dapbus_i : in dapbus_m_o;
      dapbus_o : out dapbus_m_o
      );
  end component;

  component dapbus_m_i_sync is
    port(
      clock_i : in std_ulogic;

      dapbus_i : in dapbus_m_i;
      dapbus_o : out dapbus_m_i
      );
  end component;
  
end package dapbus;
