library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc, nsl_line_coding;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_line_coding.hdlc.all;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  signal in_s, out_s: nsl_bnoc.committed.committed_bus;
  signal hdlc_s: nsl_bnoc.pipe.pipe_bus_t;

begin

  gen0: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "frame.txt"
      )
    port map(
      p_resetn => reset_n_s,
      p_clk => clock_s,
      p_out_val => in_s.req,
      p_out_ack => in_s.ack,
      p_done => done_s(0)
      );

  framer: nsl_line_coding.hdlc.hdlc_framer
    generic map(
      stuff_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      frame_i => in_s.req,
      frame_o => in_s.ack,
      hdlc_o => hdlc_s.req,
      hdlc_i => hdlc_s.ack
      );

  unframer: nsl_line_coding.hdlc.hdlc_unframer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      hdlc_i => hdlc_s.req,
      hdlc_o => hdlc_s.ack,
      frame_o => out_s.req,
      frame_i => out_s.ack
      );

  chk0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "frame.txt"
      )
    port map(
      p_resetn => reset_n_s,
      p_clk => clock_s,
      p_in_val => out_s.req,
      p_in_ack => out_s.ack,
      p_done => done_s(1)
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

  
end;
