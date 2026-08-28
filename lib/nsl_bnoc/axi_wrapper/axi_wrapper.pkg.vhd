library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc;
use nsl_amba.axi4_stream.all;

package axi_wrapper is

  component axi4_stream_chunker is
    generic(
      max_txn_length_l2_c : natural range 2 to 14 := 10;
      packet_config_c : config_t;
      chunks_config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      packet_i : in master_t;
      packet_o : out slave_t;

      chunks_o : out master_t;
      chunks_i : in slave_t
      );
  end component;

  component axi4_stream_unchunker is
    generic(
      packet_config_c : config_t;
      chunks_config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      chunks_i : in master_t;
      chunks_o : out slave_t;

      packet_o : out master_t;
      packet_i : in slave_t;

      reset_n_o : out std_ulogic
      );
  end component;

end package;
