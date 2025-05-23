library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_clocking, nsl_inet, nsl_data, nsl_mii;
use nsl_simulation.logging.all;
use nsl_mii.link.all;
use nsl_mii.rgmii.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_inet.testing.all;

architecture arch of tb is

  constant clock_hz_c : natural := 125e6;
  constant clock_period_c : time := 1000000000 ns / clock_hz_c;
  constant reset_period_c : time := clock_period_c * 7 / 2;
  
  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal done_s : std_ulogic_vector(0 to 0);

  constant a_mac_c : mac48_t := from_hex("eeddccbbaa01");
  constant a_ipv4_c : ipv4_t := to_ipv4(10,0,0,1);
  constant b_mac_c : mac48_t := from_hex("eeddccbbaa02");
  constant b_ipv4_c : ipv4_t := to_ipv4(10,0,0,2);
  constant netmask_c : ipv4_t := to_ipv4(255,255,255,0);
  constant gateway_c : ipv4_t := to_ipv4(10,0,0,254);
  constant broadcast_c : ipv4_t := to_ipv4(10,0,0,255);

  constant mode_c: link_speed_t := LINK_SPEED_1000;

  constant a_udp_port_c: udp_port_t := 1234;
  constant b_udp_port_c: udp_port_t := 4567;
  
  shared variable a_udp_txq_sv, a_udp_rxq_sv: committed_queue_root;
  shared variable b_udp_txq_sv, b_udp_rxq_sv: committed_queue_root;

  signal rgmii_a2b_s, rgmii_b2a_s : rgmii_io_group_t;

  type committed_io is
  record
    rx, tx: nsl_bnoc.committed.committed_bus;
  end record;

  signal a_udp_s, b_udp_s: committed_io;

  constant b_mode_c:string := "loopback";
  
begin

  a_udp_injector: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(a_udp_txq_sv);
    committed_wait(a_udp_s.tx.req, a_udp_s.tx.ack, clock_s, 40);
    while true
    loop
      committed_wait(a_udp_s.tx.req, a_udp_s.tx.ack, clock_s, 1);
      committed_queue_get(a_udp_txq_sv, data, valid, clock_period_c);
      log_info("A UDP < " & to_string(data.all));
      committed_put(a_udp_s.tx.req, a_udp_s.tx.ack, clock_s, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  a_udp_popper: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(a_udp_rxq_sv);
    while true
    loop
      committed_get(a_udp_s.rx.req, a_udp_s.rx.ack, clock_s, data, valid);
      log_info("A UDP > " & to_string(data.all) & ", " & to_string(valid));
      committed_queue_put(a_udp_rxq_sv, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  b_pipe: if b_mode_c = "pipe"
  generate
    b_udp_injector: process is
      variable data: byte_stream;
      variable valid: boolean;
    begin
      committed_queue_init(b_udp_txq_sv);
      committed_wait(b_udp_s.tx.req, b_udp_s.tx.ack, clock_s, 40);
      while true
      loop
        committed_wait(b_udp_s.tx.req, b_udp_s.tx.ack, clock_s, 1);
        committed_queue_get(b_udp_txq_sv, data, valid, clock_period_c);
        log_info("B UDP < " & to_string(data.all));
        committed_put(b_udp_s.tx.req, b_udp_s.tx.ack, clock_s, data.all, valid);
        deallocate(data);
      end loop;
    end process;

    b_udp_popper: process is
      variable data: byte_stream;
      variable valid: boolean;
    begin
      committed_queue_init(b_udp_rxq_sv);
      while true
      loop
        committed_get(b_udp_s.rx.req, b_udp_s.rx.ack, clock_s, data, valid);
        log_info("B UDP > " & to_string(data.all) & ", " & to_string(valid));
        committed_queue_put(b_udp_rxq_sv, data.all, valid);
        deallocate(data);
      end loop;
    end process;
  end generate;

  b_loopback: if b_mode_c = "loopback"
  generate
    b_udp_s.tx.req <= b_udp_s.rx.req;
    b_udp_s.rx.ack <= b_udp_s.tx.ack;
  end generate;
  
  udp_gen: process is
    variable tmp: byte_string(0 to 32);
  begin
    done_s(0) <= '0';

    wait for clock_period_c * 500;

    committed_queue_put(a_udp_txq_sv,
                        b_ipv4_c & to_byte(0)
                        & to_be(to_unsigned(b_udp_port_c, 16))
                        & from_hex("dead"), true);
    committed_queue_put(a_udp_txq_sv,
                        b_ipv4_c & to_byte(0)
                        & to_be(to_unsigned(b_udp_port_c, 16))
                        & from_hex("dead"), true);

    wait for clock_period_c;
    wait for clock_period_c * 500;

    committed_queue_put(a_udp_txq_sv,
                        b_ipv4_c & to_byte(0)
                        & to_be(to_unsigned(b_udp_port_c, 16))
                        & from_hex("dead"), true);

    wait for clock_period_c;
    wait for clock_period_c * 500;

    for i in 0 to 32
    loop
      for x in 0 to i
      loop
        tmp(x) := to_byte(i-x);
      end loop;

      committed_queue_put(a_udp_txq_sv,
                          b_ipv4_c & to_byte(0)
                          & to_be(to_unsigned(b_udp_port_c, 16))
                          & tmp(0 to i), true);

      wait for clock_period_c * i * 10;
    end loop;
      
    wait for clock_period_c * 500;
    done_s(0) <= '1';
    wait;
  end process;

  a: work.helper.host
    generic map(
      mac_c => a_mac_c,
      unicast_c => a_ipv4_c,
      gateway_c => gateway_c,
      netmask_c => netmask_c,
      broadcast_c => broadcast_c,
      udp_port_c => a_udp_port_c,
      clock_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      rgmii_o => rgmii_a2b_s,
      rgmii_i => rgmii_b2a_s,

      udp_tx_i => a_udp_s.tx.req,
      udp_tx_o => a_udp_s.tx.ack,
      udp_rx_o => a_udp_s.rx.req,
      udp_rx_i => a_udp_s.rx.ack,

      mode_i => mode_c
      );

  b: work.helper.host
    generic map(
      mac_c => b_mac_c,
      unicast_c => b_ipv4_c,
      gateway_c => gateway_c,
      netmask_c => netmask_c,
      broadcast_c => broadcast_c,
      udp_port_c => b_udp_port_c,
      clock_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      rgmii_o => rgmii_b2a_s,
      rgmii_i => rgmii_a2b_s,

      udp_tx_i => b_udp_s.tx.req,
      udp_tx_o => b_udp_s.tx.ack,
      udp_rx_o => b_udp_s.rx.req,
      udp_rx_i => b_udp_s.rx.ack,

      mode_i => mode_c
      );
    
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => reset_period_c,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
