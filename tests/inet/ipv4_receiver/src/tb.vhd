library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_inet, nsl_bnoc, nsl_logic;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.committed.all;
use nsl_logic.bool.all;

entity tb is
end tb;

architecture beh of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal ipv4_rx_in_s, ipv4_rx_out_s : committed_bus;
  signal done_s : std_ulogic_vector(0 to 1);

  constant source_addr_c: ipv4_t := to_ipv4(10,0,0,254);
  constant destination_addr_c: ipv4_t := to_ipv4(10,0,1,5);
  constant broadcast_addr_c: ipv4_t := to_ipv4(10,0,1,255);
  
  constant ping_pdu_c : byte_string := from_hex(
      "00005058480b00066230888a"
    & "000891d008090a0b0c0d0e0f");

  function to_received(pdu: byte_string) return byte_string
  is
    constant data: byte_string := ipv4_data_get(pdu);
    constant dlen: unsigned(15 downto 0) := to_unsigned(data'length, 16);
    constant is_bcast: boolean := ipv4_destination_get(pdu) = broadcast_addr_c;
    constant bcast_ctx: integer := if_else(is_bcast, 1, 0);
  begin
    return ipv4_source_get(pdu)
      & to_byte(bcast_ctx)
      & to_byte(ipv4_proto_get(pdu))
      & to_be(dlen)
      & data;
  end function;

  constant base_frame_c: byte_string := ipv4_pack(
    source => source_addr_c,
    destination => destination_addr_c,
    proto => ip_proto_icmp,
    data => ping_pdu_c,
    id => x"5fc9",
    ttl => 64);

begin

  ip_in: process is
  begin
    done_s(0) <= '0';
    ipv4_rx_in_s.req.valid <= '0';

    wait for 50 ns;

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  ipv4_pack(
                    source => source_addr_c,
                    destination => to_ipv4(0,1,2,3),
                    proto => ip_proto_icmp,
                    data => from_hex("00")
                    ), true);

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  ipv4_pack(
                    source => source_addr_c,
                    destination => broadcast_addr_c,
                    proto => 123,
                    data => from_hex("00")
                    ), true);

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  base_frame_c & to_byte(42) & to_byte(01), true);

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  base_frame_c(base_frame_c'left to base_frame_c'right-1), true);

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  base_frame_c, false);

    committed_put(ipv4_rx_in_s.req, ipv4_rx_in_s.ack, clock_s,
                  base_frame_c, true);
    done_s(0) <= '1';
    wait;
  end process;

  ip_out: process is
  begin
    done_s(1) <= '0';
    ipv4_rx_out_s.ack.ready <= '0';

    wait for 50 ns;

    committed_check("bad dest",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    null_byte_string, false,
                    LOG_LEVEL_FATAL);

    committed_check("proto 123",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    to_received(ipv4_pack(
                      source => source_addr_c,
                      destination => broadcast_addr_c,
                      proto => 123,
                      data => from_hex("00")
                      )), true,
                    LOG_LEVEL_FATAL);

    committed_check("long frame",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    to_received(base_frame_c), true,
                    LOG_LEVEL_FATAL);

    committed_check("short frame",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    to_received(base_frame_c), false,
                    LOG_LEVEL_FATAL);

    committed_check("canceled",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    to_received(base_frame_c), false,
                    LOG_LEVEL_FATAL);

    committed_check("check",
                    ipv4_rx_out_s.req, ipv4_rx_out_s.ack, clock_s,
                    to_received(base_frame_c), true,
                    LOG_LEVEL_FATAL);

    done_s(1) <= '1';
    wait;
  end process;

  dut: nsl_inet.ipv4.ipv4_receiver
    generic map(
      header_length_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      unicast_i => destination_addr_c,
      broadcast_i => broadcast_addr_c,

      l2_i => ipv4_rx_in_s.req,
      l2_o => ipv4_rx_in_s.ack,
      
      l4_o => ipv4_rx_out_s.req,
      l4_i => ipv4_rx_out_s.ack
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
