library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_io, nsl_hwdep, nsl_data;
use nsl_math.fixed.all;
use nsl_data.text.all;
use nsl_io.diff.all;
use nsl_hwdep.xadc.all;

entity xadc_continuous is
  generic(
    config_c : channel_config_vector;
    clock_i_hz_c: integer;
    target_sps_c: integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    pin_i : in diff_pair_vector(0 to config_c'length-1);
    value_o : out value_vector(0 to config_c'length-1)
    );
end entity;

architecture beh of xadc_continuous is

  function config_compute(cfg : channel_config_vector;
                          dclk_hz : integer;
                          sps_target : integer)
    return config_t
  is
    variable cycles_per_iteration, cycles_per_s, divisor, divisor_min, divisor_max: natural;
    variable ret : config_t;
    variable chan : channel_config_t;
  begin
    ret.channel := 0;
    ret.ext_acq := false;
    ret.event_driven := false;
    ret.bipolar := false;
    ret.ext_mux := false;
    ret.average := "00";
    ret.calib_average := false;
    ret.adc_offset_correction := true;
    ret.adc_gain_correction := true;
    ret.supply_offset_correction := true;
    ret.supply_gain_correction := true;
    ret.seq_mode := seq_mode_continuous;

    ret.power_down := false;

    assert 8000000 <= dclk_hz and dclk_hz <= 250000000
      report "DRP clock frequency is out of bounds"
      severity failure;
    
    cycles_per_iteration := 104 + 26 * cfg'length;
    cycles_per_s := cycles_per_iteration * sps_target;

    divisor := (dclk_hz + cycles_per_s - 1) / cycles_per_s;
    divisor_min := nsl_math.arith.max(2, (dclk_hz + 26000000 - 1) / 26000000);
    divisor_max := nsl_math.arith.min(255, (dclk_hz - 1000000 + 1) / 1000000);
    ret.dclk_divide := nsl_math.arith.max(divisor_min,
                                          nsl_math.arith.min(divisor_max, divisor));

    report "Using DRP clock of " & to_string(dclk_hz / 1000000) & "MHz divided by "
        & to_string(ret.dclk_divide) & ", ADCCLK is " & to_string(dclk_hz / ret.dclk_divide)
        & "Hz; " & to_string(dclk_hz / ret.dclk_divide / cycles_per_iteration) & " refreshes/sec"
      severity note;

    assert 1000000 <= dclk_hz/ret.dclk_divide and dclk_hz/ret.dclk_divide <= 26000000
      report "ADC clock frequency is out of bounds, this is a bug"
      severity failure;

    ret.seq_select := (others => '0');
    ret.chan_avg := (others => '0');
    ret.chan_bipolar := (others => '0');
    ret.chan_settling_time := (others => '0');

    ret.seq_select(8) := '1'; -- calibration enable

    for i in cfg'range
    loop
      chan := cfg(i);

      -- Dont worry about order of bits here, they'll be swapped in
      -- instantiation.
      ret.seq_select(chan.channel_no) := '1';
      if chan.averaged then
        ret.chan_avg(chan.channel_no) := '1';
      end if;
      if chan.bipolar then
        ret.chan_bipolar(chan.channel_no) := '1';
      end if;
      if chan.extended_settling_time then
        ret.chan_settling_time(chan.channel_no) := '1';
      end if;
    end loop;

    return ret;
  end function;
  
  constant xadc_config: config_t := config_compute(config_c, clock_i_hz_c, target_sps_c);

  subtype adc_src_id_t is integer range -1 to config_c'length-1;
  -- A mapping of source pair index, indexed by target pair
  type adc_src_id_vector is array(integer range 0 to 16) of adc_src_id_t;

  function adc_src_compute(cfg: channel_config_vector)
    return adc_src_id_vector
  is
    variable ret : adc_src_id_vector;
  begin
    ret := (others => -1);
    for i in cfg'range
    loop
      if cfg(i).channel_no = channel_vp then
        ret(16) := i;
      end if;
      if cfg(i).channel_no >= channel_vaux0 then
        ret(cfg(i).channel_no - channel_vaux0) := i;
      end if;
    end loop;
    return ret;
  end function;

  constant adc_src_id : adc_src_id_vector := adc_src_compute(config_c);

  signal adc_daddr: unsigned(6 downto 0);
  signal adc_din, adc_dout: std_ulogic_vector(15 downto 0);
  signal adc_drdy, adc_busy, adc_eoc, adc_eos, adc_dwe, adc_den: std_ulogic;

  signal s_v: nsl_io.diff.diff_pair_vector(0 to 16);
  signal s_drp_cmd: drp_cmd;
  signal s_drp_rsp: drp_rsp;
  signal s_conversion: conversion_control;
  signal s_status: status;

begin

  -- Generate a bunch of static assignments, in order to ensure
  -- netlister will see direct connection.
  src_map: for i in adc_src_id'range
  generate
    has_pin: if adc_src_id(i) >= 0
    generate
      s_v(i) <= pin_i(adc_src_id(i));
    end generate;
    no_pin: if adc_src_id(i) < 0
    generate
      s_v(i).p <= '0';
      s_v(i).n <= '0';
    end generate;
  end generate;
  
  xadc_inst: xadc_wrapper
    generic map(
      config_c => xadc_config
      )
    port map(
      v_i => s_v(16),
      vaux_i => s_v(0 to 15),
      drp_i => s_drp_cmd,
      drp_o => s_drp_rsp,
      conversion_i => s_conversion,
      status_o => s_status
      );

  -- Dont use this port here
  s_conversion.reset <= not reset_n_i;
  s_conversion.clock <= clock_i; -- unused, actually
  s_conversion.start <= '0';

  -- DRP loopback hack explained in UG480 v.1.10.1, "Conversion Phase", p. 72
  s_drp_cmd.clock <= clock_i;
  s_drp_cmd.addr <= resize(s_status.channel, s_drp_cmd.addr'length);
  s_drp_cmd.enable <= s_status.eoc;
  s_drp_cmd.write <= '0';
  s_drp_cmd.data <= (others => '0');

  -- Latch output values when read
  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      for i in config_c'range
      loop
        if config_c(i).channel_no = to_integer(s_status.channel)
          and s_drp_rsp.ready = '1' then
          value_o(i) <= ufixed(s_drp_rsp.data(15 downto 4));
        end if;
      end loop;
    end if;
    if reset_n_i = '0' then
      value_o <= (others => (others => '0'));
    end if;
  end process;
  
end architecture;
