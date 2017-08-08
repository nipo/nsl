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

  signal s_in_val : nsl.framed.framed_req;
  signal s_in_ack : nsl.framed.framed_ack;

  signal s_flit_val : nsl.sized.sized_req;
  signal s_flit_ack : nsl.sized.sized_ack;

  signal s_out_val : nsl.framed.framed_req;
  signal s_out_ack : nsl.framed.framed_ack;

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.framed.framed_file_reader
    generic map(
      filename => "framed.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_in_val,
      p_out_ack => s_in_ack
      );

  from_framed: nsl.sized.sized_from_framed
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_in_val,
      p_in_ack => s_in_ack,
      p_out_val => s_flit_val,
      p_out_ack => s_flit_ack
      );

  to_framed: nsl.sized.sized_to_framed
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_flit_val,
      p_in_ack => s_flit_ack,
      p_out_val => s_out_val,
      p_out_ack => s_out_ack
      );

  check: testing.framed.framed_file_checker
    generic map(
      filename => "framed.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_out_val,
      p_in_ack => s_out_ack,
      p_done => s_done(0)
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
