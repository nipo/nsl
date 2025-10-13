library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.socket.all;
use nsl_simulation.tcp_socket.all;
use nsl_amba.axi4_stream.all;

entity axi4_stream_tcp_gateway is
  generic (
    config_c : nsl_amba.axi4_stream.config_t;
    bind_port_c : natural range 1 to 65535
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    
    tx_i : in nsl_amba.axi4_stream.master_t;
    tx_o : out nsl_amba.axi4_stream.slave_t;
    
    rx_o : out nsl_amba.axi4_stream.master_t;
    rx_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of axi4_stream_tcp_gateway is

  impure function open_port(port_no: natural)
    return tcp_socket_t
  is
    variable addr: sockaddr_in_t := ((0,0,0,0), port_no);
    variable ret: tcp_socket_t;
  begin
    create_listener(addr, ret);
    return ret;
  end function;

  shared variable socket: tcp_socket_t := open_port(bind_port_c);

begin

  receiver: process is
    variable buf: byte_stream := null;
  begin
    rx_o <= transfer_defaults(config_c);

    wait until rising_edge(clock_i);
    wait until rising_edge(clock_i) and reset_n_i = '1';
    wait until rising_edge(clock_i);
    wait until falling_edge(clock_i);

    loop
      recv(socket, buf);

      if buf /= null then
        packet_send(config_c, clock_i, rx_i, rx_o, buf.all);
        deallocate(buf);
      end if;
    end loop;
  end process;

  sender: process is
    variable buf: byte_string(0 to config_c.data_width-1);
    variable beat: master_t;
    variable d: byte_string(0 to config_c.data_width-1);
    variable s, k: std_ulogic_vector(0 to config_c.data_width-1);
    variable used: natural;
  begin
    tx_o <= accept(config_c, false);

    wait until rising_edge(clock_i);
    wait until rising_edge(clock_i) and reset_n_i = '1';
    wait until rising_edge(clock_i);

    loop
      used := 0;
 
      receive(config_c, clock_i, tx_i, tx_o, beat);

      d := bytes(config_c, beat);
      s := strobe(config_c, beat);
      k := keep(config_c, beat);

      for i in d'range
      loop
        if k(i) = '1' and s(i) = '1' then
          buf(used) := d(i);
          used := used + 1;
        end if;
      end loop;

      if used /= 0 then
        send(socket, buf(0 to used-1));
      end if;
    end loop;
  end process;
  
end architecture;
