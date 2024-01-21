library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

library nsl_data;

package nsl_adaptation is

  component nsl_neorv32_rom is
    generic (
      contents_c : nsl_data.bytestream.byte_string;
      byte_count_c    : natural := 0
      );
    port (
      clk_i     : in  std_ulogic;
      rstn_i    : in  std_ulogic;
      bus_req_i : in  bus_req_t;
      bus_rsp_o : out bus_rsp_t
      );
  end component;

  component nsl_neorv32_ram is
    generic (
      byte_count_c    : natural
      );
    port (
      clk_i     : in  std_ulogic;
      rstn_i    : in  std_ulogic;
      bus_req_i : in  bus_req_t;
      bus_rsp_o : out bus_rsp_t
      );
  end component;

end package;
