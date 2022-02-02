library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag is

  component jtag_user_tap
    generic(
      user_port_count_c : integer := 1
      );
    port(
      chip_tck_i : in std_ulogic := '0';
      chip_tms_i : in std_ulogic := '0';
      chip_tdi_i : in std_ulogic := '0';
      chip_tdo_o : out std_ulogic;

      tdo_i : in std_ulogic_vector(0 to user_port_count_c-1);
      selected_o : out std_ulogic_vector(0 to user_port_count_c-1);
      run_o : out std_ulogic;
      tck_o : out std_ulogic;
      tdi_o : out std_ulogic;
      tlr_o : out std_ulogic;
      shift_o : out std_ulogic;
      capture_o : out std_ulogic;
      update_o : out std_ulogic
      );
  end component;

  component jtag_tap_register
    generic(
      id_c    : natural range 1 to 4
      );
    port(
      tck_o     : out std_ulogic;
      reset_n_o : out std_ulogic;
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
  
end package jtag;
