library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;

package simulation is

  component axi4_stream_udp_socket is
    generic(
      -- Configuration can be any data width, must have last, not strb.
      -- If has keep, short frames will be conveyed correctly.
      -- Sparse frames are not handled.
      config_c : nsl_amba.axi4_stream.config_t;
      -- By default, simply listen on local port and send frames to
      -- the peer that we received from last.
      -- If remote host and port are set, forcibly send there.
      remote_host_c : string := "";
      remote_port_c : natural := 0;
      local_port_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package simulation;
