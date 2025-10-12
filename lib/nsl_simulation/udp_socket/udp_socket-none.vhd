package body udp_socket is

  procedure create(local: sockaddr_in_t;
                   socket: out udp_socket_t)
  is
  begin
    socket := -1;
  end procedure;

  procedure sendto(socket: udp_socket_t;
                   remote: sockaddr_in_t;
                   data: byte_string)
  is
  begin
  end procedure;

  procedure recv_nonblock(socket: udp_socket_t;
                          remote: out sockaddr_in_t;
                          data: out byte_stream)
  is
  begin
    data := null;
  end procedure;

  procedure recv(socket: udp_socket_t;
                 remote: out sockaddr_in_t;
                 data: out byte_stream;
                 dt: time := 10 ns)
  is
  begin
    data := null;
  end procedure;

end package body;
