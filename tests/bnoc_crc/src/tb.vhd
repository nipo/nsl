library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  signal data_in_s, data_crc_s, data_out_s : nsl_bnoc.committed.committed_bus;

begin

  gen0: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => reset_n_s,
      p_clk => clock_s,
      p_out_val => data_in_s.req,
      p_out_ack => data_in_s.ack,
      p_done => done_s(0)
      );

  adder: nsl_bnoc.crc.crc_committed_adder
    generic map(
      header_length_c => 0,
      crc_init_c => crc_ieee_802_3_init,
      crc_poly_c => crc_ieee_802_3_poly,
      insert_msb_c => crc_ieee_802_3_insert_msb,
      pop_lsb_c => crc_ieee_802_3_pop_lsb,
      complement_c => false,
      stream_lsb_first_c => true,
      bit_reverse_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => data_in_s.req,
      in_o => data_in_s.ack,
      out_o => data_crc_s.req,
      out_i => data_crc_s.ack
      );

  stripper: nsl_bnoc.crc.crc_committed_stripper
    generic map(
      header_length_c => 0,
      crc_init_c => crc_ieee_802_3_init,
      crc_poly_c => crc_ieee_802_3_poly,
      crc_check_c => x"00000000",
      insert_msb_c => crc_ieee_802_3_insert_msb,
      pop_lsb_c => crc_ieee_802_3_pop_lsb,
      complement_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => data_crc_s.req,
      in_o => data_crc_s.ack,
      out_o => data_out_s.req,
      out_i => data_out_s.ack
      );

  chk0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => reset_n_s,
      p_clk => clock_s,
      p_in_val => data_out_s.req,
      p_in_ack => data_out_s.ack,
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
