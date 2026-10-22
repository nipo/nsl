library ieee;
use ieee.std_logic_1164.all;

library nsl_indication;

entity ip_top is
  generic(
    clock_freq_hz : natural := 100000000;
    mode : string := "change";
    idle_hz : integer := 1;
    activity_blink_hz : integer := 4;
    activity_blink_duty_pct : integer := 25
    );
  port(
    clock : in  std_logic;
    resetn : in  std_logic;

    activity : in  std_logic;
    led : out std_logic
    );
end entity;

architecture rtl of ip_top is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock : signal is "xilinx.com:signal:clock:1.0 clock CLK";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of activity : signal is "xilinx.com:signal:data:1.0 activity DATA";
  attribute X_INTERFACE_INFO of led : signal is "xilinx.com:signal:data:1.0 led DATA";

begin

  monitor: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_freq_hz),
      idle_blink_hz_c => real(idle_hz),
      mode_c => mode,
      activity_blink_hz_c => real(activity_blink_hz),
      activity_blink_duration_c => real(activity_blink_duty_pct) / 100.0
      )
    port map(
      clock_i => clock,
      reset_n_i => resetn,
      activity_i => activity,
      led_o => led
      );

end;
