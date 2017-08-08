library ieee;
use ieee.std_logic_1164.all;

library nsl;
use nsl.fifo.all;
use nsl.logic_analyzer.all;

entity tb is
end tb;

architecture arch of tb is

  constant DW : integer := 8;
  constant TW : integer := 8;
  
  signal s_resetn : std_ulogic := '0';
  signal s_clk : std_ulogic := '0';

  constant clk_period : time := 1 us;

  signal s_in_r_wok : std_ulogic;
  signal s_in_w_rok : std_ulogic;
  signal s_in_d : std_ulogic_vector(DW+TW-1 downto 0);

  signal s_mid_r_wok : std_ulogic;
  signal s_mid_w_rok : std_ulogic;
  signal s_mid_d : std_ulogic_vector(DW+TW-1 downto 0);
  
  signal s_out_r_wok : std_ulogic;
  signal s_out_w_rok : std_ulogic;
  signal s_out_d : std_ulogic_vector(DW-1 downto 0);

  signal s_io : std_ulogic_vector(DW-1 downto 0) := (others => '0');

  shared variable simend : boolean := false;
  
begin

  gen: nsl.logic_analyzer.event_monitor
    generic map(
      data_width => DW,
      delta_width => TW,
      sync_depth => 4
      )
    port map(
      p_resetn => s_resetn,
      p_clk => s_clk,

      p_in => s_io,

      p_delta => s_in_d(DW-1 downto 0),
      p_data => s_in_d(DW+TW-1 downto DW),
      p_write => s_in_w_rok
      );
  
  fifo: nsl.fifo.fifo_sync
    generic map(
      data_width => DW+TW,
      depth => 1024
    ) port map (
      p_resetn => s_resetn,
      p_clk => s_clk,
      p_out_empty_n => s_mid_w_rok,
      p_out_read => s_mid_r_wok,
      p_out_data => s_mid_d,
      p_in_full_n => s_in_r_wok,
      p_in_write => s_in_w_rok,
      p_in_data => s_in_d
    );

  narrower: nsl.fifo.fifo_narrower
    generic map(
      parts => 2,
      width_out => 8
      )
    port map(
      p_resetn  => s_resetn,
      p_clk     => s_clk,

      p_out_data    => s_out_d,
      p_out_read    => s_out_r_wok,
      p_out_empty_n => s_out_w_rok,

      p_in_data   => s_mid_d,
      p_in_write  => s_mid_w_rok,
      p_in_full_n => s_mid_r_wok
      );

  clock_gen: process(s_clk)
  begin
    if not simend then
      s_clk <= not s_clk after clk_period / 2;
    end if;
  end process;

  s_resetn <= '1' after clk_period;

  process
  begin
    s_out_r_wok <= '1';
    wait for clk_period * 14.5;
    s_io <= x"a0";
    wait for clk_period;
    s_io <= x"b0";
    wait for clk_period * 50;
    s_io <= x"15";
    wait for clk_period;
    s_io <= x"ff";
    wait for clk_period;
    s_io <= x"df";
    wait for clk_period * 257;
    s_io <= x"00";
    wait for clk_period * 4;
    s_out_r_wok <= '0';
    wait for clk_period * 2;
    s_out_r_wok <= '1';
    wait for clk_period;
    s_out_r_wok <= '0';
    wait for clk_period;
    s_out_r_wok <= '1';
    wait for clk_period;
    s_out_r_wok <= '0';
    wait for clk_period;
    s_out_r_wok <= '1';

    simend := true;
    wait;
  end process;
  
end;
