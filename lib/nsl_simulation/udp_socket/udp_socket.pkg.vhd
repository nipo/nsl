library nsl_data;
use nsl_data.bytestream.all;

package udp_socket is

  subtype nibble is integer range 0 to 255;
  type ipv4_t is array(integer range 0 to 3) of nibble;

  type sockaddr_in_t is
  record
    ip: ipv4_t;
    prt: integer range 0 to 65535;
  end record;

  subtype udp_socket_t is integer;
  
  procedure create(local: sockaddr_in_t;
                   socket: out udp_socket_t);

  procedure sendto(socket: udp_socket_t;
                   remote: sockaddr_in_t;
                   data: byte_string);

  procedure recv_nonblock(socket: udp_socket_t;
                          remote: out sockaddr_in_t;
                          data: out byte_stream);

  procedure recv(socket: udp_socket_t;
                 remote: out sockaddr_in_t;
                 data: out byte_stream;
                 dt: time := 10 ns);
  
end package;
