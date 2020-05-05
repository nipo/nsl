library ieee;
use ieee.std_logic_1164.all;

library nsl_indication;

entity activity_monitor is
  generic(
    freq_hz : natural := 100000000;
    on_value : std_ulogic := '1'
    );
  port(
    clk    : in  std_logic;
    resetn : in  std_logic;

    changing : in  std_logic;
    activity : out std_logic
    );
end entity;

architecture rtl of activity_monitor is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";
  
begin

  monitor: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => freq_hz / 8,
      on_value_c => on_value
      )
    port map(
      reset_n_i => resetn,
      clock_i => clk,
      togglable_i => changing,
      activity_o => activity
      );
  
end;
