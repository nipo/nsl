library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_clocking, nsl_inet, nsl_data;
use nsl_simulation.logging.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;
use nsl_inet.tcp.all;
use nsl_inet.testing.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.binary_io.all;
use nsl_data.text.all;

architecture arch of tb is

  constant clock_hz_c : natural := 4000;
  constant clock_period_c : time := 1000000000 ns / clock_hz_c;
  constant reset_period_c : time := clock_period_c * 7 / 2;
  
  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;
  
  signal chk_in_s, chk_out_s : nsl_bnoc.committed.committed_bus;
  shared variable chk_in_q, chk_out_q: committed_queue_root;
  
  signal done_s : std_ulogic_vector(0 to 1);

  constant dut_ipv4_c : ipv4_t := to_ipv4(10,0,0,1);
  constant gateway_ipv4_c : ipv4_t := to_ipv4(10,0,0,254);
  constant netmask_ipv4_c : ipv4_t := to_ipv4(255,255,255,0);
  constant broadcast_ipv4_c : ipv4_t := to_ipv4(10,0,0,255);
  constant foreign_ipv4_c : ipv4_t := to_ipv4(10,0,1,1);
    
begin

  injector: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(chk_in_q);
    committed_wait(chk_in_s.req, chk_in_s.ack, clock_s, 40);
    while true
    loop
      committed_wait(chk_in_s.req, chk_in_s.ack, clock_s, 64/8);
      committed_queue_get(chk_in_q, data, valid, clock_period_c);
      ethernet_dump("IP < ", data.all, false);
      committed_put(chk_in_s.req, chk_in_s.ack, clock_s, data.all, valid);
      deallocate(data);
    end loop;
  end process;

  popper: process is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    committed_queue_init(chk_out_q);
    while true
    loop
      wait for clock_period_c * 96 / 8;
      committed_get(chk_out_s.req, chk_out_s.ack, clock_s, data, valid);
      if not valid then
        log_info("IP * Frame not valid");
        log_info("IP * " & to_string(data.all));
        ethernet_dump("IP * ", data.all, false);
      else
        ethernet_dump("IP > ", data.all, false);
      end if;
      committed_queue_put(chk_out_q, data.all, valid);
      deallocate(data);
    end loop;
  end process;
  
  inserter: process is
    file fd : binary_file;
    variable header : pcap_header_t;
    variable packet : pcap_packet_t;
    variable status: file_open_status;
  begin
    done_s(0) <= '0';
    file_open(status => status,
              f => fd,
              external_name => "dump.pcap",
              open_kind => READ_MODE);

    if status /= OPEN_OK then
      log_info("Opening dump file failed");
      done_s(0) <= '1';
      wait;
    end if;

    pcap_read(fd, header);

    if not header.is_valid then
      log_info("not a pcap file");
      file_close(fd);
      done_s(0) <= '1';
      wait;
    end if;
    
    wait for clock_period_c * 100;

    while not endfile(fd)
    loop
      pcap_read(fd, header, packet);

      committed_queue_put(chk_in_q, packet.data.all, true);

      pcap_packet_free(packet);
    end loop;

    file_close(fd);

    done_s(0) <= '1';
    wait;
  end process;

  checker: process is
    file fd : binary_file;
    variable header : pcap_header_t;
    variable packet : pcap_packet_t;
    variable status: file_open_status;
  begin
    done_s(1) <= '0';
    file_open(status => status,
              f => fd,
              external_name => "dump.pcap",
              open_kind => READ_MODE);

    if status /= OPEN_OK then
      log_info("Opening dump file failed");
      done_s(1) <= '1';
      wait;
    end if;

    pcap_read(fd, header);

    if not header.is_valid then
      log_info("not a pcap file");
      file_close(fd);
      done_s(1) <= '1';
      wait;
    end if;
    
    wait for clock_period_c * 100;

    while not endfile(fd)
    loop
      pcap_read(fd, header, packet);

      committed_queue_check("check", chk_out_q, packet.data.all, true, level => LOG_LEVEL_ERROR);

      pcap_packet_free(packet);
    end loop;

    file_close(fd);

    done_s(1) <= '1';
    wait;
  end process;
  
  checksummer: nsl_inet.ipv4.ipv4_checksum_inserter
    generic map(
      header_length_c => 14
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      output_o => chk_out_s.req,
      output_i => chk_out_s.ack,

      input_i => chk_in_s.req,
      input_o => chk_in_s.ack
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
