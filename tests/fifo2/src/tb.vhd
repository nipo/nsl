library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library nsl;
use nsl.util.all;
use nsl.fifo.all;
library testing;
use testing.fifo.all;

architecture arch of tb is

  constant width : integer := 8;
  
  signal s_left_val : std_ulogic;
  signal s_left_ack : std_ulogic;
  signal s_left_data : std_ulogic_vector(width-1 downto 0);

  signal s_right_val : std_ulogic;
  signal s_right_ack : std_ulogic;
  signal s_right_data : std_ulogic_vector(width-1 downto 0);

  signal s_clk : std_ulogic := '0';
  signal s_clk2 : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_clk2 : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic;

  shared variable simend : boolean := false;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  reset_sync_clk2: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk2,
      p_clk => s_clk2
      );

  gen: testing.fifo.fifo_file_reader
    generic map(
      width => width,
      filename => "input.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_empty_n => s_left_val,
      p_read => s_left_ack,
      p_data => s_left_data,
      p_done => s_done
      );

  fifo2: nsl.fifo.fifo_async
    generic map(
      data_width => width,
      depth => 8
      )
    port map(
      p_resetn => s_resetn_async,

      p_in_clk => s_clk,
      p_in_data => s_left_data,
      p_in_write => s_left_val,
      p_in_full_n => s_left_ack,

      p_out_clk => s_clk2,
      p_out_data => s_right_data,
      p_out_read => s_right_ack,
      p_out_empty_n => s_right_val
      );

  sink: testing.fifo.fifo_file_checker
    generic map(
      width => width,
      filename => "input.txt"
      )
    port map(
      p_resetn => s_resetn_clk2,
      p_clk => s_clk2,
      p_full_n => s_right_ack,
      p_data => s_right_data,
      p_write => s_right_val
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait until rising_edge(s_done);
    wait until falling_edge(s_right_val);
    wait for 100 ns;
    simend := true;
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if not simend then
      s_clk <= not s_clk after 7 ns;
    end if;
  end process;

  clock_gen2: process(s_clk2)
  begin
    if not simend then
      s_clk2 <= not s_clk2 after 29 ns;
    end if;
  end process;

end;
