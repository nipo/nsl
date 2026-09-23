library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_io;

package xadc is

  subtype channel_no_t is integer range 0 to 31;
  constant channel_temp     : channel_no_t := 00;
  constant channel_vccint   : channel_no_t := 01;
  constant channel_vccaux   : channel_no_t := 02;
  constant channel_vp       : channel_no_t := 03;
  constant channel_vrefp    : channel_no_t := 04;
  constant channel_vrefn    : channel_no_t := 05;
  constant channel_vccbram  : channel_no_t := 06;
  constant channel_vccpint  : channel_no_t := 13;
  constant channel_vccapux  : channel_no_t := 14;
  constant channel_vcco_ddr : channel_no_t := 15;
  constant channel_vaux0    : channel_no_t := 16;
  constant channel_vaux1    : channel_no_t := 17;
  constant channel_vaux2    : channel_no_t := 18;
  constant channel_vaux3    : channel_no_t := 19;
  constant channel_vaux4    : channel_no_t := 20;
  constant channel_vaux5    : channel_no_t := 21;
  constant channel_vaux6    : channel_no_t := 22;
  constant channel_vaux7    : channel_no_t := 23;
  constant channel_vaux8    : channel_no_t := 24;
  constant channel_vaux9    : channel_no_t := 25;
  constant channel_vaux10   : channel_no_t := 26;
  constant channel_vaux11   : channel_no_t := 27;
  constant channel_vaux12   : channel_no_t := 28;
  constant channel_vaux13   : channel_no_t := 29;
  constant channel_vaux14   : channel_no_t := 30;
  constant channel_vaux15   : channel_no_t := 31;

  constant alarm_temp : integer := 0;
  constant alarm_vccint : integer := 1;
  constant alarm_vccaux : integer := 2;
  constant alarm_vccbram : integer := 3;
  constant alarm_vccpint : integer := 4;
  constant alarm_vccpaux : integer := 5;
  constant alarm_vcco_ddr : integer := 6;

  subtype seq_mode_t is std_ulogic_vector(3 downto 0);
  constant seq_mode_default        : seq_mode_t := "0000";
  constant seq_mode_single_pass    : seq_mode_t := "0001";
  constant seq_mode_continuous     : seq_mode_t := "0010";
  constant seq_mode_single_channel : seq_mode_t := "0011";
  constant seq_mode_simultaneous   : seq_mode_t := "0100";
  constant seq_mode_independent    : seq_mode_t := "1000";
  
  -- Encoding for 0..1V.
  subtype value_t is nsl_math.fixed.ufixed(-1 downto -12);
  type value_vector is array(channel_no_t range <>) of value_t;

  function voltage_to_adc(volts: real) return value_t;
  function temperature_to_adc(celcius: real) return value_t;
  
  type alarm_range is
  record
    upper, lower: real;
  end record;

  type config_t is
  record
    -- config0
    channel: channel_no_t;
    ext_acq, event_driven, bipolar, ext_mux: boolean;
    average: std_ulogic_vector(1 downto 0);
    -- Enable (inverted before register)
    calib_average: boolean;

    -- config1
    -- Alarms are inferred from alarm configs
    -- Calibration
    adc_offset_correction,
      adc_gain_correction,
      supply_offset_correction,
      supply_gain_correction: boolean;
    seq_mode: seq_mode_t;

    -- config2
    power_down: boolean;
    dclk_divide: integer range 2 to 255;

    seq_select, chan_avg, chan_bipolar, chan_settling_time: std_ulogic_vector(31 downto 0);
  end record;

  type alarms is
  record
    -- In volts or Celcius
    temp, ot, vccint, vccaux, vccbram, vccpint, vccpaux, vcco_ddr: alarm_range;
  end record;

  constant alarms_none : alarms := (
    temp     => (upper => 0.0, lower => 0.0),
    ot       => (upper => 0.0, lower => 0.0),
    vccint   => (upper => 0.0, lower => 0.0),
    vccaux   => (upper => 0.0, lower => 0.0),
    vccbram  => (upper => 0.0, lower => 0.0),
    vccpint  => (upper => 0.0, lower => 0.0),
    vccpaux  => (upper => 0.0, lower => 0.0),
    vcco_ddr => (upper => 0.0, lower => 0.0)
    );

  type drp_cmd is
  record
    clock: std_ulogic;
    addr: unsigned(6 downto 0);
    data: std_ulogic_vector(15 downto 0);
    enable, write: std_ulogic;
  end record;

  type drp_rsp is
  record
    data: std_ulogic_vector(15 downto 0);
    ready: std_ulogic;
  end record;
  
  type conversion_control is
  record
    reset, start, clock: std_ulogic;
  end record;
  
  type alarm is
  record
    alarm: std_ulogic_vector(6 downto 0);
    any : std_ulogic;
    ot : std_ulogic;
  end record;
  
  type status is
  record
    mux_addr, channel: unsigned(4 downto 0);
    eoc, eos, busy : std_ulogic;
    jtag_locked, jtag_modified, jtag_busy: std_ulogic;
  end record;

  -- Nearly a one-to-one mapping of XADC primitive, with a few sugars:
  -- - Abstract configuration generic,
  -- - High-level ports with proper typing.
  component xadc_wrapper is
    generic(
      config_c : config_t;
      alarms_c : alarms := (others => (lower => 0.0, upper => 0.0))
      );
    port(
      v_i : in nsl_io.diff.diff_pair;
      vaux_i : in nsl_io.diff.diff_pair_vector(0 to 15);
      drp_i: in drp_cmd;
      drp_o: out drp_rsp;
      conversion_i: in conversion_control;
      alarm_o: out alarm;
      status_o: out status
      );
  end component;  

  type channel_config_t is
  record
    channel_no : channel_no_t;
    enabled, averaged, bipolar, extended_settling_time: boolean;
  end record;

  type channel_config_vector is array(natural range <>) of channel_config_t;

  -- Abstract component that takes care of:
  -- - static configuration of block,
  -- - handling sequence,
  -- - converting outputs,
  -- - extracting useful output signals.
  --
  -- It is passed an array of needed channels. Output values will
  -- match indices from configuration array.
  component xadc_continuous is
    generic(
      config_c : channel_config_vector;
      clock_i_hz_c: integer;
      target_sps_c: integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pin_i : in nsl_io.diff.diff_pair_vector(0 to config_c'length-1);
      -- Always a ufixed. If port is actually used as differential,
      -- type cast to sfixed should be performed by caller.
      value_o : out value_vector(0 to config_c'length-1)
      );
  end component;

end package;

package body xadc is

  use nsl_math.fixed.all;

  function voltage_to_adc(volts: real) return value_t
  is
  begin
    return to_ufixed(volts / 3.0,
                     value_t'left, value_t'right);
  end function;

  function temperature_to_adc(celcius: real) return value_t
  is
  begin
    return to_ufixed((celcius + 273.15) / 503.975,
                     value_t'left, value_t'right);
  end function;

end package body;
