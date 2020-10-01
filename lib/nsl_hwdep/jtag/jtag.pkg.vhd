library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag is
  component jtag_tap_register
    generic(
      id_c    : natural range 1 to 4
      );
    port(
      tck_o     : out std_ulogic;
      reset_o   : out std_ulogic;
      selected_o: out std_ulogic;
      capture_o : out std_ulogic;
      shift_o   : out std_ulogic;
      update_o  : out std_ulogic;
      tdi_o     : out std_ulogic;
      tdo_i     : in  std_ulogic
      );
  end component;

  component jtag_reg
    generic(
      width_c : integer;
      id_c    : natural
      );
    port(
      clock_o    : out std_ulogic;
      reset_n_o  : out std_ulogic;
      
      data_o     : out std_ulogic_vector(width_c-1 downto 0);
      update_o   : out std_ulogic;

      data_i     : in std_ulogic_vector(width_c-1 downto 0);
      capture_o  : out std_ulogic
      );
  end component;

  component jtag_inbound_fifo
    generic(
      id_c      : natural
      );
    port(
      clock_o   : out std_ulogic;
      reset_n_o : out std_ulogic;
      sync_i    : in  std_ulogic_vector;
      data_o    : out std_ulogic_vector;
      valid_o   : out std_ulogic
      );
  end component;

  component jtag_outbound_fifo
    generic(
      id_c      : natural
      );
    port(
      clock_o   : out std_ulogic;
      reset_n_o : out std_ulogic;
      data_i    : in std_ulogic_vector;
      ready_o   : out std_ulogic
      );
  end component;
  
end package jtag;
