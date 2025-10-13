use std.textio.all;

package body tcp_socket is

  procedure tcp_socket_create_listener(local: sockaddr_in_t;
                                       socket: out tcp_socket_t)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_create_listener: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_create_listener";

  procedure tcp_socket_create_connect(remote: sockaddr_in_t;
                                      socket: out tcp_socket_t)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_create_connect: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_create_connect";

  procedure tcp_socket_is_connected(socket: inout tcp_socket_t;
                                    status: out boolean)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_is_connected: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_is_connected";

  procedure tcp_socket_send(socket: inout tcp_socket_t;
                            data: string)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_send: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_send";

  procedure tcp_socket_recv_len(socket: inout tcp_socket_t; rlen: out integer)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_recv_len: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_recv_len";

  procedure tcp_socket_recv_data(socket: inout tcp_socket_t;
                                 data: inout string;
                                 rlen: inout integer)
  is
  begin
    assert false report "Should not be called" severity failure;
  end procedure;

  attribute foreign of tcp_socket_recv_data: procedure is "VHPIDIRECT tcp_socket-vhpidirect.so tcp_socket_recv_data";

  procedure create_listener(local: sockaddr_in_t;
                            socket: out tcp_socket_t)
  is
  begin
    tcp_socket_create_listener(local, socket);
  end procedure;

  procedure create_connect(remote: sockaddr_in_t;
                           socket: out tcp_socket_t)
  is
  begin
    tcp_socket_create_connect(remote, socket);
  end procedure;

  procedure is_connected(socket: inout tcp_socket_t;
                         status: out boolean)
  is
  begin
    tcp_socket_is_connected(socket, status);
  end procedure;

  procedure send(socket: inout tcp_socket_t;
                 data: byte_string)
  is
  begin
    tcp_socket_send(socket, to_character_string(data));
  end procedure;

  procedure recv_nonblock(socket: inout tcp_socket_t;
                          data: out byte_stream)
  is
    variable len: integer;
    variable tmp: line;
    variable ret: byte_stream;
  begin
    tcp_socket_recv_len(socket, len);
    data := null;

    if len <= 0 then
      return;
    end if;

    tmp := new string(1 to len);
    tcp_socket_recv_data(socket, tmp.all, len);

    if len = 0 then
      deallocate(tmp);
      return;
    end if;

    ret := new byte_string(0 to len-1);
    ret.all := to_byte_string(tmp.all(1 to len));
    deallocate(tmp);
    data := ret;
  end procedure;

  procedure recv(socket: inout tcp_socket_t;
                 data: out byte_stream;
                 dt: time := 10 ns)
  is
    variable d: byte_stream;
  begin
    deallocate(d);
    while d = null
    loop
      recv_nonblock(socket, d);
      if d /= null then
        data := d;
        return;
      end if;
      wait for dt;
    end loop;
  end procedure;

end package body;
