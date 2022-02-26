library ieee;
use ieee.std_logic_1164.all;

package fifo is

  component jtag_inbound_fifo
    generic(
      id_c      : natural
      );
    port(
      clock_i        : in  std_ulogic;
      reset_n_i      : in  std_ulogic;
      jtag_reset_n_o : out std_ulogic;
      data_o         : out std_ulogic_vector;
      last_o         : out std_ulogic;
      valid_o        : out std_ulogic;
      ready_i        : in  std_ulogic
      );
  end component;

  component jtag_outbound_fifo
    generic(
      id_c      : natural
      );
    port(
      clock_i        : in  std_ulogic;
      reset_n_i      : in  std_ulogic;
      jtag_reset_n_o : out std_ulogic;
      data_i         : in  std_ulogic_vector;
      valid_i        : in  std_ulogic;
      last_i         : in  std_ulogic;
      ready_o        : out std_ulogic
      );
  end component;

end package;
