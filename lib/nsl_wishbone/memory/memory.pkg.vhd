library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.wishbone.all;

package memory is

  component wishbone_rom is
    generic(
      wb_config_c : wb_config_t;
      contents_c : nsl_data.bytestream.byte_string
      );
    port(
      clock_i : std_ulogic;
      reset_n_i : std_ulogic;

      wb_i : in wb_req_t;
      wb_o : out wb_ack_t
      );
  end component;

  component wishbone_ram is
    generic(
      wb_config_c : wb_config_t;
      byte_size_l2_c : natural
      );
    port(
      clock_i : std_ulogic;
      reset_n_i : std_ulogic;

      wb_i : in wb_req_t;
      wb_o : out wb_ack_t
      );
  end component;

end package memory;
