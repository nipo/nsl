library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
library testing;
library util;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 downto 0);

  signal n_val : nsl.framed.framed_req_array(1 downto 0);
  signal n_ack : nsl.framed.framed_ack_array(1 downto 0);

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.framed.framed_file_reader
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => n_val(0),
      p_out_ack => n_ack(0)
      );

  check: testing.framed.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => n_val(1),
      p_in_ack => n_ack(1),
      p_done => s_done(0)
      );

  fifo: nsl.framed.framed_fifo_atomic
    generic map(
      depth => 8
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk(0) => s_clk,
      p_in_val => n_val(0),
      p_in_ack => n_ack(0),
      p_out_val => n_val(1),
      p_out_ack => n_ack(1)
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;
  
end;
