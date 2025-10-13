package body tcp_socket is

  procedure create_listener(local: sockaddr_in_t;
                            socket: out tcp_socket_t)
  is
  begin
    socket := (-1, -1);
  end procedure;

  procedure create_connect(remote: sockaddr_in_t;
                           socket: out tcp_socket_t)
  is
  begin
    socket := (-1, -1);
  end procedure;

  procedure is_connected(socket: inout tcp_socket_t;
                         status: out boolean)
  is
  begin
    status := false;
  end procedure;

  procedure send(socket: inout tcp_socket_t;
                 data: byte_string)
  is
  begin
  end procedure;

  procedure recv_nonblock(socket: inout tcp_socket_t;
                          data: out byte_stream)
  is
  begin
    data := null;
  end procedure;

  procedure recv(socket: inout tcp_socket_t;
                 data: out byte_stream;
                 dt: time := 10 ns)
  is
  begin
    data := null;
  end procedure;

end package body;
