library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_amba, nsl_data, nsl_simulation;
use nsl_bnoc.pipe.all;
use nsl_bnoc.testing.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal pipe_in_s, pipe_out_s : pipe_bus_t;
  signal axi_s : bus_t;

  constant test_data_c : byte_string(0 to 63) := (
    x"00", x"01", x"02", x"03", x"04", x"05", x"06", x"07",
    x"08", x"09", x"0a", x"0b", x"0c", x"0d", x"0e", x"0f",
    x"10", x"11", x"12", x"13", x"14", x"15", x"16", x"17",
    x"18", x"19", x"1a", x"1b", x"1c", x"1d", x"1e", x"1f",
    x"20", x"21", x"22", x"23", x"24", x"25", x"26", x"27",
    x"28", x"29", x"2a", x"2b", x"2c", x"2d", x"2e", x"2f",
    x"30", x"31", x"32", x"33", x"34", x"35", x"36", x"37",
    x"38", x"39", x"3a", x"3b", x"3c", x"3d", x"3e", x"3f"
  );

begin

  sender: process is
  begin
    pipe_in_s.req <= pipe_req_idle_c;
    wait for 40 ns;
    pipe_write(pipe_in_s.req, pipe_in_s.ack, clock_s, test_data_c);
    wait;
  end process;

  receiver: process is
    variable rx_data : byte_string(0 to 63);
  begin
    done_s(0) <= '0';
    pipe_out_s.ack <= pipe_ack_idle_c;
    wait for 40 ns;

    pipe_read(pipe_out_s.req, pipe_out_s.ack, clock_s, rx_data);

    assert rx_data = test_data_c
      report "Pipe data mismatch"
      severity failure;

    log_info("Pipe adapter test passed");
    done_s(0) <= '1';
    wait;
  end process;

  pipe_to_axi: nsl_bnoc.axi_adapter.pipe_to_axi4_stream
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pipe_i => pipe_in_s.req,
      pipe_o => pipe_in_s.ack,

      axi_o => axi_s.m,
      axi_i => axi_s.s
      );

  axi_to_pipe: nsl_bnoc.axi_adapter.axi4_stream_to_pipe
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      pipe_o => pipe_out_s.req,
      pipe_i => pipe_out_s.ack
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
