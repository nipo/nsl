library ieee;
use ieee.std_logic_1164.all;

library util, hwdep;

entity i2c_glitch_filter is
  generic(
    cycle_count : positive range 1 to 10000 := 5
    );
  port(
    raw_sda_i : in std_logic;
    raw_sda_o : out std_logic;
    raw_sda_t : out std_logic;
    raw_scl_i : in std_logic;
    raw_scl_o : out std_logic;
    raw_scl_t : out std_logic;

    filtered_sda_i : out std_logic;
    filtered_sda_o : in std_logic;
    filtered_sda_t : in std_logic;
    filtered_scl_i : out std_logic;
    filtered_scl_o : in std_logic;
    filtered_scl_t : in std_logic
    );
end entity;

architecture rtl of i2c_glitch_filter is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of raw_sda_i : signal is "xilinx.com:interface:iic:1.0 raw SDA_I";
  attribute X_INTERFACE_INFO of raw_sda_o : signal is "xilinx.com:interface:iic:1.0 raw SDA_O";
  attribute X_INTERFACE_INFO of raw_sda_t : signal is "xilinx.com:interface:iic:1.0 raw SDA_T";
  attribute X_INTERFACE_INFO of raw_scl_i : signal is "xilinx.com:interface:iic:1.0 raw SCL_I";
  attribute X_INTERFACE_INFO of raw_scl_o : signal is "xilinx.com:interface:iic:1.0 raw SCL_O";
  attribute X_INTERFACE_INFO of raw_scl_t : signal is "xilinx.com:interface:iic:1.0 raw SCL_T";

  attribute X_INTERFACE_INFO of filtered_sda_i : signal is "xilinx.com:interface:iic:1.0 filtered SDA_I";
  attribute X_INTERFACE_INFO of filtered_sda_o : signal is "xilinx.com:interface:iic:1.0 filtered SDA_O";
  attribute X_INTERFACE_INFO of filtered_sda_t : signal is "xilinx.com:interface:iic:1.0 filtered SDA_T";
  attribute X_INTERFACE_INFO of filtered_scl_i : signal is "xilinx.com:interface:iic:1.0 filtered SCL_I";
  attribute X_INTERFACE_INFO of filtered_scl_o : signal is "xilinx.com:interface:iic:1.0 filtered SCL_O";
  attribute X_INTERFACE_INFO of filtered_scl_t : signal is "xilinx.com:interface:iic:1.0 filtered SCL_T";
  
  signal deglitch_clock : std_ulogic;
  
begin

  clk: hwdep.clock.clock_internal
    port map(
      p_clk => deglitch_clock
      );

  sda_deglitch: util.sync.sync_deglitcher
    generic map(
      cycle_count => cycle_count
      )
    port map(
      p_clk => deglitch_clock,
      p_in => raw_sda_i,
      p_out => filtered_sda_i
      );

  scl_deglitch: util.sync.sync_deglitcher
    generic map(
      cycle_count => cycle_count
      )
    port map(
      p_clk => deglitch_clock,
      p_in => raw_scl_i,
      p_out => filtered_scl_i
      );

  raw_sda_t <= filtered_sda_t;
  raw_sda_o <= filtered_sda_o;
  raw_scl_t <= filtered_scl_t;
  raw_scl_o <= filtered_scl_o;

end;
