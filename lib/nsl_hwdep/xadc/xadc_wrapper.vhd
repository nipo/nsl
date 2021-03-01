library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_io, nsl_hwdep, unisim, nsl_logic;
use nsl_math.fixed.all;
use nsl_hwdep.xadc.all;
use nsl_logic.bool.all;

entity xadc_wrapper is
  generic(
    config_c : config_t;
    alarms_c : alarms := alarms_none
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
end entity;

architecture beh of xadc_wrapper is

  function alarm_v(voltage: real) return bit_vector
  is
  begin
    return to_bitvector(to_suv(voltage_to_adc(voltage)) & "0000");
  end function;

  function alarm_t(celcius: real;
                   enabled: boolean := false) return bit_vector
  is
  begin
    if enabled then
      return to_bitvector(to_suv(temperature_to_adc(celcius)) & "0011");
    else
      return to_bitvector(to_suv(temperature_to_adc(celcius)) & "0000");
    end if;
  end function;

  function config0(cfg: config_t) return bit_vector
  is
    variable ret: bit_vector(15 downto 0) := (others => '0');
  begin
    ret(4 downto 0) := to_bitvector(std_ulogic_vector(to_unsigned(cfg.channel, 5)));
    ret(8) := to_bit(to_logic(cfg.ext_acq));
    ret(9) := to_bit(to_logic(cfg.event_driven));
    ret(10) := to_bit(to_logic(cfg.bipolar));
    ret(11) := to_bit(to_logic(cfg.ext_mux));
    ret(13 downto 12) := to_bitvector(cfg.average);
    ret(15) := to_bit(to_logic(not cfg.calib_average));

    return ret;
  end function;

  function config1(cfg: config_t;
                   alm: alarms) return bit_vector
  is
    variable ret: bit_vector(15 downto 0) := (others => '0');
  begin
    -- These are disables, only disable if both limits are 0.
    ret(0) := to_bit(to_logic(alm.ot.lower = 0.0 and alm.ot.upper = 0.0));
    ret(1) := to_bit(to_logic(alm.temp.lower = 0.0 and alm.temp.upper = 0.0));
    ret(2) := to_bit(to_logic(alm.vccint.lower = 0.0 and alm.vccint.upper = 0.0));
    ret(3) := to_bit(to_logic(alm.vccaux.lower = 0.0 and alm.vccaux.upper = 0.0));
    ret(8) := to_bit(to_logic(alm.vccbram.lower = 0.0 and alm.vccbram.upper = 0.0));
    ret(9) := to_bit(to_logic(alm.vccpint.lower = 0.0 and alm.vccpint.upper = 0.0));
    ret(10) := to_bit(to_logic(alm.vccpaux.lower = 0.0 and alm.vccpaux.upper = 0.0));
    ret(11) := to_bit(to_logic(alm.vcco_ddr.lower = 0.0 and alm.vcco_ddr.upper = 0.0));

    ret(4) := to_bit(to_logic(cfg.adc_offset_correction));
    ret(5) := to_bit(to_logic(cfg.adc_gain_correction));
    ret(6) := to_bit(to_logic(cfg.supply_offset_correction));
    ret(7) := to_bit(to_logic(cfg.supply_gain_correction));

    ret(15 downto 12) := to_bitvector(cfg.seq_mode);
 
    return ret;
  end function;

  function config2(cfg: config_t) return bit_vector
  is
    variable ret: bit_vector(15 downto 0) := (others => '0');
  begin
    if cfg.power_down then
      ret(5 downto 4) := "11";
    end if;
    ret(15 downto 8) := to_bitvector(std_ulogic_vector(to_unsigned(cfg.dclk_divide, 8)));
    return ret;
  end function;

  function channel_map_low(channel_map: std_ulogic_vector) return bit_vector
  is
  begin
    return to_bitvector(channel_map(7 downto 0) & channel_map(15 downto 8));
  end function;

  function channel_map_high(channel_map: std_ulogic_vector) return bit_vector
  is
  begin
    return to_bitvector(channel_map(31 downto 16));
  end function;

  signal vauxp, vauxn: std_logic_vector(15 downto 0);

  signal drp_o_data : std_logic_vector(15 downto 0);
  signal status_o_channel, status_o_mux_addr : std_logic_vector(4 downto 0);
  signal alarm_o_alarm : std_logic_vector(7 downto 0);
  
begin

  xadc: unisim.vcomponents.xadc
    generic map(
      init_40 => config0(config_c),
      init_41 => config1(config_c, alarms_c),
      init_42 => config2(config_c),
      init_48 => channel_map_low(config_c.seq_select),
      init_49 => channel_map_high(config_c.seq_select),
      init_4a => channel_map_low(config_c.chan_avg),
      init_4b => channel_map_high(config_c.chan_avg),
      init_4c => channel_map_low(config_c.chan_bipolar),
      init_4d => channel_map_high(config_c.chan_bipolar),
      init_4e => channel_map_low(config_c.chan_settling_time),
      init_4f => channel_map_high(config_c.chan_settling_time),
      init_50 => alarm_t(alarms_c.temp.upper, alarms_c.temp.upper /= 0.0),
      init_51 => alarm_v(alarms_c.vccint.upper),
      init_52 => alarm_v(alarms_c.vccaux.upper),
      init_53 => alarm_t(alarms_c.ot.upper),
      init_54 => alarm_t(alarms_c.temp.lower),
      init_55 => alarm_v(alarms_c.vccint.lower),
      init_56 => alarm_v(alarms_c.vccaux.lower),
      init_57 => alarm_t(alarms_c.ot.lower),
      init_58 => alarm_v(alarms_c.vccbram.upper),
      init_59 => alarm_v(alarms_c.vccpint.upper),
      init_5a => alarm_v(alarms_c.vccpaux.upper),
      init_5b => alarm_v(alarms_c.vcco_ddr.upper),
      init_5c => alarm_v(alarms_c.vccbram.lower),
      init_5d => alarm_v(alarms_c.vccpint.lower),
      init_5e => alarm_v(alarms_c.vccpaux.lower),
      init_5f => alarm_v(alarms_c.vcco_ddr.lower)
      )
    port map(
      vauxp => vauxp,
      vauxn => vauxn,
      vp => v_i.p,
      vn => v_i.n,

      dclk => drp_i.clock,
      di => std_logic_vector(drp_i.data),
      daddr => std_logic_vector(drp_i.addr),
      den => drp_i.enable,
      dwe => drp_i.write,
      do => drp_o_data,
      drdy => drp_o.ready,

      reset => conversion_i.reset,
      convst => conversion_i.start,
      convstclk => conversion_i.clock,

      alm => alarm_o_alarm,
      ot => alarm_o.ot,

      busy => status_o.busy,
      muxaddr => status_o_mux_addr,
      channel => status_o_channel,
      eoc => status_o.eoc,
      eos => status_o.eos,
      jtagbusy => status_o.jtag_busy,
      jtaglocked => status_o.jtag_locked,
      jtagmodified => status_o.jtag_modified
      );

  drp_o.data <= std_ulogic_vector(drp_o_data);
  status_o.channel <= unsigned(status_o_channel);
  status_o.mux_addr <= unsigned(status_o_mux_addr);
  alarm_o.alarm <= std_ulogic_vector(alarm_o_alarm(6 downto 0));
  alarm_o.any <= alarm_o_alarm(7);

  vmap: for i in 0 to 15
  generate
    vauxp(i) <= vaux_i(i).p;
    vauxn(i) <= vaux_i(i).n;
  end generate;
  
end architecture;
