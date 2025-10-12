library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;

package udp_socket is

  use nsl_simulation.socket.all;

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
