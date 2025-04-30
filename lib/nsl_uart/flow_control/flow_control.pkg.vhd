library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc;
use nsl_data.bytestream.all;

package flow_control is

  component xonxoff_rx is
    generic(
      xoff_c: byte := x"13";
      xon_c: byte := x"11";
      extra_rx_depth_c : natural := 2;
      timeout_after_c : natural := 0
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      -- Enable flow control, if not enabled, assume TX and RX are
      -- infinite
      enable_i : in std_ulogic := '1';

      peer_ready_o : out std_ulogic;
      rx_ready_o : out std_ulogic;
      
      serdes_i : in nsl_bnoc.pipe.pipe_req_t;
      serdes_o : out nsl_bnoc.pipe.pipe_ack_t;

      rx_o : out nsl_bnoc.pipe.pipe_req_t;
      rx_i : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;

  component xonxoff_tx is
    generic(
      xoff_c: byte := x"13";
      xon_c: byte := x"11";
      refresh_every_c : integer := 0
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      -- Enable flow control transmission and limiting
      enable_i : in std_ulogic := '1';

      -- Gates the TX path, controlled by RX side's "Peer ready" signal
      can_transmit_i : in std_ulogic := '1';
      -- Tells whether to send XON or XOFF
      can_receive_i : in std_ulogic := '1';

      tx_i : in nsl_bnoc.pipe.pipe_req_t;
      tx_o : out nsl_bnoc.pipe.pipe_ack_t;

      serdes_o : out nsl_bnoc.pipe.pipe_req_t;
      serdes_i : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;

end package flow_control;
