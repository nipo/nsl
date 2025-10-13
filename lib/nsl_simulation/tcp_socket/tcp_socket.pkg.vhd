library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;

package tcp_socket is

  use nsl_simulation.socket.all;
  
  type tcp_socket_t is
  record
    listen_fd, sock_fd: integer;
  end record;
  
  procedure create_listener(local: sockaddr_in_t;
                            socket: out tcp_socket_t);

  procedure create_connect(remote: sockaddr_in_t;
                           socket: out tcp_socket_t);

  procedure is_connected(socket: inout tcp_socket_t;
                         status: out boolean);

  procedure send(socket: inout tcp_socket_t;
                   data: byte_string);

  procedure recv_nonblock(socket: inout tcp_socket_t;
                          data: out byte_stream);

  procedure recv(socket: inout tcp_socket_t;
                 data: out byte_stream;
                 dt: time := 10 ns);
  
end package;
