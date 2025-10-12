package body udp_socket is

  procedure udp_socket_create(local: sockaddr_in_t;
                              socket: out udp_socket_t)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of udp_socket_create: procedure is "VHPIDIRECT udp_socket-vhpidirect.so udp_socket_create";

  procedure udp_socket_sendto(socket: udp_socket_t;
                              remote: sockaddr_in_t;
                              data: string)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of udp_socket_sendto: procedure is "VHPIDIRECT udp_socket-vhpidirect.so udp_socket_sendto";

  function udp_socket_recv_len(socket: udp_socket_t) return integer
  is
  begin
    assert false report "Should not be called" severity failure;
  end function;

  attribute foreign of udp_socket_recv_len: function is "VHPIDIRECT udp_socket-vhpidirect.so udp_socket_recv_len";

  procedure udp_socket_recv_data(socket: udp_socket_t;
                                 remote: out sockaddr_in_t;
                                 data: inout string;
                                 rlen: inout integer)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of udp_socket_recv_data: procedure is "VHPIDIRECT udp_socket-vhpidirect.so udp_socket_recv_data";

  procedure create(local: sockaddr_in_t;
                   socket: out udp_socket_t)
  is
  begin
    udp_socket_create(local, socket);
  end procedure;

  procedure sendto(socket: udp_socket_t;
                   remote: sockaddr_in_t;
                   data: byte_string)
  is
  begin
    udp_socket_sendto(socket, remote, to_character_string(data));
  end procedure;

  procedure recv_nonblock(socket: udp_socket_t;
                          remote: out sockaddr_in_t;
                          data: out byte_stream)
  is
    constant available_len: integer := udp_socket_recv_len(socket);
    variable tmp: string(1 to available_len);
    variable ret: byte_stream;
    variable rlen: integer;
  begin
    data := null;
    if available_len <= 0 then
      return;
    end if;
    udp_socket_recv_data(socket, remote, tmp, rlen);
    ret := new byte_string(0 to rlen-1);
    ret.all := to_byte_string(tmp(1 to rlen));
    data :=ret;
  end procedure;

  procedure recv(socket: udp_socket_t;
                 remote: out sockaddr_in_t;
                 data: out byte_stream;
                 dt: time := 10 ns)
  is
    variable d: byte_stream;
  begin
    deallocate(d);
    while d = null
    loop
      recv_nonblock(socket, remote, d);
      if d /= null then
        data := d;
        return;
      end if;
      wait for dt;
    end loop;
  end procedure;

end package body;
