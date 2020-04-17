library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package stream is

  component axis_fifo is
    generic(
      depth        : natural;
      data_bytes   : natural;
      tid_width    : natural := 0;
      tdest_width  : natural := 0;
      tuser_width  : natural := 0;
      clk_count    : natural range 1 to 2
      );
    port(
      aresetn     : in  std_ulogic;

      s_clk       : in std_ulogic;
      s_tvalid    : in std_ulogic;
      s_tready    : out std_ulogic;
      s_tdata     : in std_ulogic_vector(data_bytes * 8 - 1 downto 0);
      s_tstrb     : in std_ulogic_vector(data_bytes - 1 downto 0) := (data_bytes - 1 downto 0 => '1');
      s_keep      : in std_ulogic_vector(data_bytes - 1 downto 0) := (data_bytes - 1 downto 0 => '1');
      s_last      : in std_ulogic;
      s_tid       : in std_ulogic_vector(tid_width - 1 downto 0) := (tid_width - 1 downto 0 => '0');
      s_tdest     : in std_ulogic_vector(tdest_width - 1 downto 0) := (tdest_width - 1 downto 0 => '0');
      s_tuser     : in std_ulogic_vector(tuser_width - 1 downto 0) := (tuser_width - 1 downto 0 => '0');

      m_clk       : in std_ulogic := '-';
      m_tvalid    : out std_ulogic;
      m_tready    : in std_ulogic;
      m_tdata     : out std_ulogic_vector(data_bytes * 8 - 1 downto 0);
      m_tstrb     : out std_ulogic_vector(data_bytes - 1 downto 0);
      m_keep      : out std_ulogic_vector(data_bytes - 1 downto 0);
      m_last      : out std_ulogic;
      m_tid       : out std_ulogic_vector(tid_width - 1 downto 0);
      m_tdest     : out std_ulogic_vector(tdest_width - 1 downto 0);
      m_tuser     : out std_ulogic_vector(tuser_width - 1 downto 0);
      );
  end component;

end package axis;
