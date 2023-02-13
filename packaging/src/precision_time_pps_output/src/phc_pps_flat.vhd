library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_event, nsl_time;

entity phc_pps_flat is
  generic(
    clock_rate_hz: integer := 100e6;
    pulse_duration_ms: integer := 100;
    offset_ns: integer := 0
    );
  port(
    clock : in std_logic;
    reset_n : in std_logic;

    timestamp_second: in std_logic_vector(31 downto 0);
    timestamp_nanosecond: in std_logic_vector(29 downto 0);
    timestamp_abs_change: in std_logic;
    
    pps: out std_logic
    );
end entity;

architecture rtl of phc_pps_flat is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock : signal is "xilinx.com:signal:clock:1.0 clock CLK";
  attribute X_INTERFACE_INFO of reset_n : signal is "xilinx.com:signal:reset:1.0 reset_n RST";

  attribute X_INTERFACE_INFO of timestamp_second : signal is "nsl:interface:phc_timestamp:1.0 timestamp SECOND";
  attribute X_INTERFACE_INFO of timestamp_nanosecond : signal is "nsl:interface:phc_timestamp:1.0 timestamp NANOSECOND";
  attribute X_INTERFACE_INFO of timestamp_abs_change : signal is "nsl:interface:phc_timestamp:1.0 timestamp ABS_CHANGE";

  attribute X_INTERFACE_PARAMETER of clock : signal is "ASSOCIATED_BUSIF timestamp, ASSOCIATED_RESET reset_n";
  attribute X_INTERFACE_PARAMETER of reset_n : signal is "POLARITY ACTIVE_LOW";

  signal ts, ts_offsetted: nsl_time.timestamp.timestamp_t;
  constant pipeline_delay_cycles : integer := 0
                                              + 2 -- pps_ticker
                                              + 3 -- skew_offsetter
                                              + 1 -- tick_pulse
                                              ;
  constant clock_rate_mhz : real := real(clock_rate_hz) / 1.0e6;
  constant corrected_offset_ns: integer := offset_ns - integer(pipeline_delay_cycles * 1.0e3 / clock_rate_mhz);
  constant corrected_offset_ns_signed : nsl_time.timestamp_t.timestamp_nanosecond_offset_t := to_signed(corrected_offset_ns, nsl_time.timestamp_t.timestamp_nanosecond_offset_t'length);
  signal tick: std_ulogic;
  
begin

  ts <= nsl_time.timestamp.from_sl(timestamp_second, timestamp_nanosecond, timestamp_abs_change);
  
  has_offset: if corrected_offset_ns /= 0
  generate
    offsetter: nsl_time.skew.skew_offsetter
      port map(
        clock_i => clock,
        reset_n_i => reset_n,

        reference_i => ts,
        offset_i => corrected_offset_ns_signed,

        skew_o => ts_offsetted
        );
  end generate;

  no_offset: if corrected_offset_ns = 0
  generate
    ts_offsetted <= ts;
  end generate;

  ts_pps_ticker: nsl_time.pps.pps_ticker
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      reference_i => ts_offsetted,
      tick_o => tick
      );
  
  pps_pulse: nsl_event.tick.tick_pulse
    generic map(
      clock_hz_c => clock_rate_hz,
      assert_sec_c => real(pulse_duration_ms) * 1.0e-3
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      tick_i => tick,
      pulse_o => pps
      );
  
end architecture;
