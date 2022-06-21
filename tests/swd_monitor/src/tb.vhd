library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_coresight;
use nsl_coresight.dp.all;

architecture arch of tb is
  procedure shift(signal swclk: in std_ulogic;
                  signal swdio: out std_ulogic;
                  constant dio: in std_ulogic) is
  begin
    swdio <= dio;
    wait until rising_edge(swclk);
    wait until falling_edge(swclk);
  end procedure;

  procedure shift(signal swclk: in std_ulogic;
                  signal swdio: out std_ulogic;
                  constant stream: in std_ulogic_vector) is
  begin
    for i in stream'range
    loop
      shift(swclk, swdio, stream(i));
    end loop;
  end procedure;

  procedure run(signal swclk: in std_ulogic;
                signal swdio: out std_ulogic;
                constant cycles: integer) is
  begin
    for i in 0 to cycles - 1
    loop
      shift(swclk, swdio, '0');
    end loop;
  end procedure;

  procedure reset(signal swclk: in std_ulogic;
                  signal swdio: out std_ulogic;
                  constant cycles: integer) is
  begin
    for i in 0 to cycles - 1
    loop
      shift(swclk, swdio, '1');
    end loop;
  end procedure;

  signal s_done : std_ulogic_vector(0 to 0);
  signal s_swdio, s_swclk, s_clock, s_reset_n: std_ulogic;
  signal s_state: dp_state_t;
  signal s_tech: dp_tech_t;

  constant swd_to_jtag_c : std_ulogic_vector := "0011110011100111";
  constant jtag_to_swd_c : std_ulogic_vector := "0111100111100111";
  constant jtag_to_ds_c : std_ulogic_vector := "0101110111011101110111011100110";
  constant swd_to_ds_c : std_ulogic_vector := "0011110111000111";
  constant ds_alert_c : std_ulogic_vector := x"49CF9046_A9B4A161_97F5BBC7_45703D98";
  constant ds_jtag_serial_c : std_ulogic_vector := "0000000000000000";
  constant ds_arm_sw_dp_c : std_ulogic_vector := "000001011000";
  constant ds_arm_jtag_dp_c : std_ulogic_vector := "000001010000";

begin

  s_swclk <= s_clock;

  stim: process is
  begin
    s_swdio <= '-';
    s_done(0) <= '0';
    wait for 200 ns;

    -- Initital state.
    -- Is in SWD.
    
    reset(s_swclk, s_swdio, 100);
    assert s_state = DP_RESET severity note;
    assert s_tech = DP_TECH_SWD severity note;

    run(s_swclk, s_swdio, 100);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_SWD severity note;

    reset(s_swclk, s_swdio, 50);
    assert s_state = DP_RESET severity note;
    assert s_tech = DP_TECH_SWD severity note;

    -- Try switching to JTAG-DP and back
    
    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_JTAG severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_SWD severity note;

    -- Switch to dormant, ensure JTAG<->SWD sequences do nothing
    
    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_ds_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    -- Switch from Dormant to JTAG

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, ds_alert_c);
    shift(s_swclk, s_swdio, ds_arm_jtag_dp_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_JTAG severity note;

    -- Switch to dormant, ensure JTAG<->SWD sequences do nothing

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_ds_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    -- Switch to SW-DP, ensure JTAG<->SWD sequences work
    
    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, ds_alert_c);
    shift(s_swclk, s_swdio, ds_arm_sw_dp_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_SWD severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_SWD severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_JTAG severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_state = DP_ACTIVE severity note;
    assert s_tech = DP_TECH_SWD severity note;

    -- Switch to dormant, ensure JTAG<->SWD sequences do nothing

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_ds_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_DORMANT severity note;

    -- Switch to JTAG-Serial
    
    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, ds_alert_c);
    shift(s_swclk, s_swdio, ds_jtag_serial_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_JTAG_SERIAL severity note;

    -- Ensure JTAG<->SWD sequences do nothing

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, jtag_to_swd_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_JTAG_SERIAL severity note;

    reset(s_swclk, s_swdio, 50);
    shift(s_swclk, s_swdio, swd_to_jtag_c);
    reset(s_swclk, s_swdio, 50);
    run(s_swclk, s_swdio, 2);
    assert s_tech = DP_TECH_JTAG_SERIAL severity note;

    s_done(0) <= '1';
    
    wait;
  end process;

  monitor: nsl_coresight.dp.dp_monitor
    port map(
      reset_n_i => s_reset_n,
      state_o => s_state,
      tech_o => s_tech,
      dp_i.clk => s_swclk,
      dp_i.dio => s_swdio
      );
  
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_reset_n,
      clock_o(0) => s_clock,
      done_i => s_done
      );

end;
