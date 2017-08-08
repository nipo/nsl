library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library util;
use util.sync.all;

library nsl;
use nsl.fifo.all;

library testing;
use testing.fifo.all;

architecture arch of tb is

  constant width : integer := 8;
  
  signal s_left_val : std_ulogic;
  signal s_left_ack : std_ulogic;
  signal s_left_data : std_ulogic_vector(width-1 downto 0);

  signal s_mid_val : std_ulogic;
  signal s_mid_ack : std_ulogic;
  signal s_mid_data : std_ulogic_vector(width-1 downto 0);

  signal s_right_val : std_ulogic;
  signal s_right_ack : std_ulogic;
  signal s_right_data : std_ulogic_vector(width-1 downto 0);

  signal s_clk : std_ulogic := '0';
  signal s_clk2 : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_clk2 : std_ulogic;
  signal s_resetn_async : std_ulogic;

  shared variable simend : boolean := false;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  reset_sync_clk2: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk2,
      p_clk => s_clk2
      );

  gen: testing.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_empty_n => s_left_val,
      p_read => s_left_ack,
      p_data => s_left_data
      );

  check: testing.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_clk2,
      p_clk => s_clk2,
      p_full_n => s_right_ack,
      p_write => s_right_val,
      p_data => s_right_data
      );

  fifo1: nsl.fifo.fifo_sync
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_in_data => s_left_data,
      p_in_write => s_left_val,
      p_in_full_n => s_left_ack,

      p_out_data => s_mid_data,
      p_out_read => s_mid_ack,
      p_out_empty_n => s_mid_val
      );

  fifo2: nsl.fifo.fifo_async
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_async,

      p_in_clk => s_clk,
      p_in_data => s_mid_data,
      p_in_write => s_mid_val,
      p_in_full_n => s_mid_ack,

      p_out_clk => s_clk2,
      p_out_data => s_right_data,
      p_out_read => s_right_ack,
      p_out_empty_n => s_right_val
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait for 1 us;
    simend := true;
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if not simend then
      s_clk <= not s_clk after 3 ns;
    end if;
  end process;

  clock_gen2: process(s_clk2)
  begin
    if not simend then
      s_clk2 <= not s_clk2 after 7 ns;
    end if;
  end process;

end;
