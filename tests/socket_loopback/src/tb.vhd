library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_simulation.socket.all;

entity tb is
end entity;

architecture beh of tb is

  constant localhost: ipv4_t := (127, 0, 0, 1);
  signal udp_done, tcp_done: boolean := false;

begin

  udp: process
    variable s: nsl_simulation.udp_socket.udp_socket_t;
    variable remote: sockaddr_in_t;
    variable d: byte_stream;
  begin
    nsl_simulation.udp_socket.create((localhost, 47101), s);
    assert s >= 0
      report "UDP socket creation failed"
      severity failure;
    nsl_simulation.udp_socket.sendto(s, (localhost, 47101), from_hex("deadbeef"));
    nsl_simulation.udp_socket.recv(s, remote, d);
    assert d.all = from_hex("deadbeef")
      report "UDP payload mismatch"
      severity failure;
    assert remote = (localhost, 47101)
      report "UDP remote address mismatch"
      severity failure;
    deallocate(d);
    udp_done <= true;
    wait;
  end process;

  tcp: process
    variable server, client: nsl_simulation.tcp_socket.tcp_socket_t;
    variable connected: boolean;
    variable d: byte_stream;
  begin
    nsl_simulation.tcp_socket.create_listener((localhost, 47102), server);
    assert server.listen_fd >= 0
      report "TCP listener creation failed"
      severity failure;
    nsl_simulation.tcp_socket.create_connect((localhost, 47102), client);
    assert client.sock_fd >= 0
      report "TCP connection failed"
      severity failure;

    loop
      nsl_simulation.tcp_socket.is_connected(server, connected);
      exit when connected;
      wait for 10 ns;
    end loop;

    nsl_simulation.tcp_socket.send(client, from_hex("0123456789"));
    nsl_simulation.tcp_socket.recv(server, d);
    assert d.all = from_hex("0123456789")
      report "TCP client to server payload mismatch"
      severity failure;
    deallocate(d);

    nsl_simulation.tcp_socket.send(server, from_hex("cafe"));
    nsl_simulation.tcp_socket.recv(client, d);
    assert d.all = from_hex("cafe")
      report "TCP server to client payload mismatch"
      severity failure;
    deallocate(d);

    tcp_done <= true;
    wait;
  end process;

  watchdog: process
  begin
    wait until udp_done and tcp_done for 1 ms;
    assert udp_done and tcp_done
      report "Loopback timed out"
      severity failure;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
