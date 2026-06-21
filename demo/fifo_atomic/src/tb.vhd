library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation, nsl_clocking;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal s_done : std_ulogic_vector(0 to 1);

  signal n_val : nsl_bnoc.framed.framed_req_array(1 downto 0);
  signal n_ack : nsl_bnoc.framed.framed_ack_array(1 downto 0);

begin

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk(0),
      p_clk => s_clk(0),
      p_out_val => n_val(0),
      p_out_ack => n_ack(0),
      p_done => s_done(0)
      );

  check: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk(1),
      p_clk => s_clk(1),
      p_in_val => n_val(1),
      p_in_ack => n_ack(1),
      p_done => s_done(1)
      );

  fifo: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      clk_count => s_clk'length,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_clk(0),
      p_clk => s_clk,
      p_in_val => n_val(0),
      p_in_ack => n_ack(0),
      p_out_val => n_val(1),
      p_out_ack => n_ack(1)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => s_clk'length,
      reset_count => s_resetn_clk'length,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 8 ns,
      reset_duration(0) => 15 ns,
      reset_duration(1) => 12 ns,
      reset_n_o => s_resetn_clk,
      clock_o => s_clk,
      done_i => s_done
      );
  
end;
