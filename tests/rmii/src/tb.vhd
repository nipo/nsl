library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
use nsl.util.all;
use nsl.fifo.all;
use nsl.mii.all;

library testing;
use testing.fifo.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_framed_val : fifo_framed_cmd_array(1 downto 0);
  signal s_framed_ack : fifo_framed_rsp_array(1 downto 0);

  signal s_rmii_data   : rmii_datapath;

  signal s_done : std_ulogic;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.fifo.fifo_framed_file_reader
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_framed_val(0),
      p_out_ack => s_framed_ack(0),
      p_done => open
      );

  check0: testing.fifo.fifo_framed_file_checker
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_framed_val(1),
      p_in_ack => s_framed_ack(1),
      p_done => s_done
      );

  to_rmii: nsl.mii.rmii_from_framed
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_rmii_data => s_rmii_data,
      p_framed_val => s_framed_val(0),
      p_framed_ack => s_framed_ack(0)
      );

  from_rmii: nsl.mii.rmii_to_framed
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_rmii_data => s_rmii_data,
      p_framed_val => s_framed_val(1),
      p_framed_ack => s_framed_ack(1)
      );
    
  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= '1' then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;