library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

package sync is

  component sync_multi_resetn
    generic(
      cycle_count : natural := 2;
      clk_count : natural
      );
    port (
      p_clk : in  std_ulogic_vector(0 to clk_count-1);
      p_resetn  : in  std_ulogic;
      p_resetn_sync : out std_ulogic_vector(0 to clk_count-1)
      );
  end component;

  component sync_rising_edge
    generic(
      cycle_count : natural := 2;
      async_reset : boolean := true
      );
    port (
      p_clk : in  std_ulogic;
      p_in  : in  std_ulogic;
      p_out : out std_ulogic
      );
  end component;

  component sync_deglitcher
    generic(
      cycle_count : natural := 2
      );
    port (
      p_clk : in  std_ulogic;
      p_in  : in  std_ulogic;
      p_out : out std_ulogic
      );
  end component;

  component sync_reg is
    generic(
      cycle_count : natural range 1 to 40 := 1;
      data_width : integer;
      cross_region : boolean := true;
      async_sampler : boolean := false
      );
    port(
      p_clk    : in std_ulogic;
      p_in     : in std_ulogic_vector(data_width-1 downto 0);
      p_out    : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  -- Basic multi-cycle synchronous register pipeline.  Mostly suited
  -- for retiming.
  component sync_multi_reg is
    generic(
      cycle_count : natural range 1 to 40 := 1;
      data_width : integer
      );
    port(
      p_clk    : in std_ulogic;
      p_in     : in std_ulogic_vector(data_width-1 downto 0);
      p_out    : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  -- Enforces max skew for the whole bus will not be above the fastest
  -- clock cycle time. Mostly suited for gray-coded data.
  component sync_cross_reg is
    generic(
      cycle_count : natural range 2 to 40 := 2;
      data_width : integer
      );
    port(
      p_clk    : in std_ulogic;
      p_in     : in std_ulogic_vector(data_width-1 downto 0);
      p_out    : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  -- Asynchronous signal sampler. Totally ignores the timing of input
  -- port, and tries to cope with metastability.
  component sync_async_reg is
    generic(
      cycle_count : natural range 2 to 40 := 2;
      data_width : integer
      );
    port(
      p_clk    : in std_ulogic;
      p_in     : in std_ulogic_vector(data_width-1 downto 0);
      p_out    : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  component sync_cross_counter is
    generic(
      cycle_count : natural := 2;
      data_width : integer;
      decode_stage_count : natural := 1;
      input_is_gray : boolean := false;
      output_is_gray : boolean := false
      );
    port(
      p_in_clk : in std_ulogic;
      p_out_clk : in std_ulogic;
      p_in  : in unsigned(data_width-1 downto 0);
      p_out : out unsigned(data_width-1 downto 0)
      );
  end component;

  component sync_input is
    generic (
      N: integer := 2
      );
    port (
      p_clk: in std_ulogic;
      p_resetn: in std_ulogic;
      p_input: in std_ulogic;
      p_output: out std_ulogic;
      p_rise: out std_ulogic;
      p_fall: out std_ulogic
      );
  end component;

end package sync;