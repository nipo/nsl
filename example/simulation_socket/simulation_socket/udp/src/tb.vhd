library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.udp_socket.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
  
begin

  x: process is
    constant local: sockaddr_in_t := ((0,0,0,0), 1234);
    constant remote: sockaddr_in_t := ((127,0,0,1), 4567);
    variable peer: sockaddr_in_t;
    variable socket: udp_socket_t;
    variable ret: integer;
    variable buf: byte_stream := null;
  begin
    create(local, socket);
    log_info("socket: "&to_string(socket));
    sendto(socket, remote, to_byte_string("Hello, world" & CR & LF));

    for i in 0 to 1
    loop
      recv(socket, peer, buf);
      wait for 0 ps;

      log_info("Received data: "&to_string(buf.all));
      sendto(socket, peer, to_byte_string("OK" & CR & LF));
    end loop;
      
    wait;
  end process;
  
end;

