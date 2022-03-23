library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc, nsl_inet;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_data.crc.all;
use nsl_simulation.assertions.all;
use nsl_bnoc.testing.all;
use nsl_inet.ethernet.fcs_params_c;
use nsl_inet.ethernet.frame_pack;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  signal adder_in_s, adder_crc_s : nsl_bnoc.committed.committed_bus;
  signal checker_crc_s, checker_out_s : nsl_bnoc.committed.committed_bus;
  constant packet_c : byte_string := from_hex( "20cf301acea16238e0c2bd3008060001"
                                               &"0800060400016238e0c2bd300a2a2a01"
                                               &"0000000000000a2a2a02000000000000"
                                               &"00000000000000000000000022b72660");

begin

  adder_gen: process
  begin
    adder_in_s.req.valid <= '0';

    wait for 100 ns;
    committed_put(adder_in_s.req, adder_in_s.ack, clock_s,
                  packet_c(packet_c'left to packet_c'right-4), true);
    wait;
  end process;

  adder_chk: process
  begin
    done_s(0) <= '0';

    adder_crc_s.ack.ready <= '0';
    wait for 100 ns;

    committed_check("adder check",
                    adder_crc_s.req, adder_crc_s.ack, clock_s,
                    packet_c, true, LOG_LEVEL_FATAL);
    done_s(0) <= '1';
    wait;
  end process;
  
  adder: nsl_bnoc.crc.crc_committed_adder
    generic map(
      header_length_c => 0,
      params_c => fcs_params_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => adder_in_s.req,
      in_o => adder_in_s.ack,
      out_o => adder_crc_s.req,
      out_i => adder_crc_s.ack
      );

  checker_gen: process
  begin
    checker_crc_s.req.valid <= '0';

    wait for 100 ns;
    committed_put(checker_crc_s.req, checker_crc_s.ack, clock_s,
                  packet_c, true);
    wait;
  end process;

  checker_chk: process
  begin
    done_s(1) <= '0';

    checker_out_s.ack.ready <= '0';
    wait for 100 ns;

    committed_check("checker check",
                    checker_out_s.req, checker_out_s.ack, clock_s,
                    packet_c(packet_c'left to packet_c'right-4), true, LOG_LEVEL_FATAL);
    done_s(1) <= '1';
    wait;
  end process;

  checker: nsl_bnoc.crc.crc_committed_checker
    generic map(
      header_length_c => 0,
      params_c => fcs_params_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => checker_crc_s.req,
      in_o => checker_crc_s.ack,
      out_o => checker_out_s.req,
      out_i => checker_out_s.ack
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
