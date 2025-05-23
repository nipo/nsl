library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_inet, nsl_bnoc;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_inet.ipv4.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.committed.all;

entity tb is
end tb;

architecture beh of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal a_tx_s, a_to_b_s, a_to_b_chk_s, b_rx_s : committed_bus;
  signal done_s : std_ulogic_vector(0 to 1);

  constant a_addr_c: ipv4_t := to_ipv4(10,0,1,1);
  constant b_addr_c: ipv4_t := to_ipv4(10,0,1,2);
  constant broadcast_addr_c: ipv4_t := to_ipv4(10,0,1,255);

  constant broken: byte_string(0 to 40) := (others => x"ee");
  
begin

  a_gen: process is
  begin
    done_s(0) <= '0';
    a_tx_s.req.valid <= '0';
    wait for 150 ns;
    framed_flit_put(a_tx_s.req, a_tx_s.ack, clock_s, x"00", false, false);

    committed_put(a_tx_s.req, a_tx_s.ack, clock_s,
                  b_addr_c & from_hex("00") & to_byte(ip_proto_icmp)
                  & from_hex("000477778888"), true);

    for i in 1 to 20
    loop
      committed_put(a_tx_s.req, a_tx_s.ack, clock_s,
                    broken(0 to i-1), true);
      committed_put(a_tx_s.req, a_tx_s.ack, clock_s,
                    broken(0 to i-1), false);
    end loop;
      
    committed_put(a_tx_s.req, a_tx_s.ack, clock_s,
                  broadcast_addr_c & from_hex("00") & to_byte(ip_proto_icmp)
                  & from_hex("000477778888"), false);

    committed_put(a_tx_s.req, a_tx_s.ack, clock_s,
                  broadcast_addr_c & from_hex("00") & to_byte(ip_proto_icmp)
                  & from_hex("000477778888"), true);
    
    done_s(0) <= '1';
    wait;
  end process;

  b_chk: process is
  begin
    done_s(1) <= '0';

    b_rx_s.ack.ready <= '0';

    committed_check("chk", b_rx_s.req, b_rx_s.ack, clock_s,
                    a_addr_c & from_hex("00") & to_byte(ip_proto_icmp)
                    & from_hex("000477778888"), true);

    for i in 1 to 20
    loop
      committed_check("chk", b_rx_s.req, b_rx_s.ack, clock_s,
                      null_byte_string, false);

      committed_check("chk", b_rx_s.req, b_rx_s.ack, clock_s,
                      null_byte_string, false);
    end loop;

    committed_check("chk", b_rx_s.req, b_rx_s.ack, clock_s,
                    a_addr_c & from_hex("01") & to_byte(ip_proto_icmp)
                    & from_hex("000477778888"), false);

    committed_check("chk", b_rx_s.req, b_rx_s.ack, clock_s,
                    a_addr_c & from_hex("01") & to_byte(ip_proto_icmp)
                    & from_hex("000477778888"), true);

    wait for 150 ns;

    done_s(1) <= '1';
    wait;
  end process;

  a: nsl_inet.ipv4.ipv4_transmitter
    generic map(
      header_length_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      unicast_i => a_addr_c,

      l4_i => a_tx_s.req,
      l4_o => a_tx_s.ack,
      
      l2_o => a_to_b_s.req,
      l2_i => a_to_b_s.ack
      );

  chk: nsl_inet.ipv4.ipv4_checksum_inserter
    generic map(
      header_length_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      input_i => a_to_b_s.req,
      input_o => a_to_b_s.ack,

      output_o => a_to_b_chk_s.req,
      output_i => a_to_b_chk_s.ack
      );
  
  b: nsl_inet.ipv4.ipv4_receiver
    generic map(
      header_length_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      unicast_i => b_addr_c,
      broadcast_i => broadcast_addr_c,

      l2_i => a_to_b_chk_s.req,
      l2_o => a_to_b_chk_s.ack,
      
      l4_o => b_rx_s.req,
      l4_i => b_rx_s.ack
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 17 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
