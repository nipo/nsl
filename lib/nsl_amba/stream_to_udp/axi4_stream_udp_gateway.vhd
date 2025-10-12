library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.socket.all;
use nsl_simulation.udp_socket.all;
use nsl_amba.axi4_stream.all;

entity axi4_stream_udp_gateway is
  generic (
    config_c : nsl_amba.axi4_stream.config_t;
    bind_port_c : natural range 1 to 65535
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    id_i: in std_ulogic_vector(config_c.id_width-1 downto 0) := (others => '0');
    dest_i: in std_ulogic_vector(config_c.dest_width-1 downto 0) := (others => '0');
    user_i: in std_ulogic_vector(config_c.user_width-1 downto 0) := (others => '0');
    
    tx_i : in nsl_amba.axi4_stream.master_t;
    tx_o : out nsl_amba.axi4_stream.slave_t;
    
    rx_o : out nsl_amba.axi4_stream.master_t;
    rx_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of axi4_stream_udp_gateway is

  impure function open_port(port_no: natural)
    return udp_socket_t
  is
    variable addr: sockaddr_in_t := ((0,0,0,0), port_no);
    variable ret: udp_socket_t;
  begin
    create(addr, ret);
    return ret;
  end function;

  shared variable socket: udp_socket_t := open_port(bind_port_c);
  shared variable peer: sockaddr_in_t;

begin

  receiver: block is
    shared variable q: frame_queue_root_t;
  begin
    network: process is
      variable buf: byte_stream := null;
    begin
      frame_queue_init(q);

      while true
      loop
        wait until rising_edge(clock_i);

        recv(socket, peer, buf);

        if buf /= null then
          frame_queue_put(q, buf.all,
                          dest => dest_i,
                          id => id_i,
                          user => user_i);
          deallocate(buf);
        end if;
      end loop;
    end process;

    signals: process is
    begin
      rx_o <= transfer_defaults(config_c);

      wait until rising_edge(clock_i);
      wait until rising_edge(clock_i) and reset_n_i = '1';
      wait until rising_edge(clock_i);
      frame_queue_master(config_c, q, clock_i, rx_i, rx_o);
    end process;
  end block;

  sender: block is
    shared variable q: frame_queue_root_t;
  begin
    signals: process is
    begin
      tx_o <= accept(config_c, false);

      wait until rising_edge(clock_i);
      wait until rising_edge(clock_i) and reset_n_i = '1';
      wait until rising_edge(clock_i);
      frame_queue_slave(config_c, q, clock_i, tx_i, tx_o);
    end process;

    network: process is
      variable buf: byte_stream := null;
      variable frame: frame_t;
    begin
      frame_queue_init(q);

      wait until rising_edge(clock_i);

      while true
      loop
        frame_queue_get(q, frame, timeout => 0 ps);
        sendto(socket, peer, frame.data.all);
        deallocate(frame.data);
      end loop;
    end process;
  end block;
  
end architecture;
