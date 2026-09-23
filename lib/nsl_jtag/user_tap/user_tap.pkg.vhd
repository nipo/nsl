library ieee;
use ieee.std_logic_1164.all;

package user_tap is

  -- node_vendor_c, node_type_c and node_version_c name what the user
  -- chains carry, for backends that let a host discover it.  On Altera
  -- parts, the chains are a virtual JTAG node whose identity word the
  -- SLD hub reports: manufacturer, type and version, laid out like the
  -- fields of a JTAG IDCODE.  Other backends have nowhere to put an
  -- identity and ignore all three.
  --
  -- The manufacturer is an 11-bit JEP106 code, continuation count over
  -- identification code.  NSL's is 0x5ff, bank 11 and code 0x7f, a
  -- code JEP106 never assigns in any bank.  A user owning another such
  -- space passes its own, and a type only means something within its
  -- manufacturer's space.
  --
  -- NSL types:
  -- 0x00: nothing stated.
  -- 0x01: nsl_jtag.continuous_transport, carrying framed bytes.
  component jtag_user_tap
    generic(
      user_port_count_c : integer := 1;
      node_vendor_c : natural range 0 to 2047 := 16#5ff#;
      node_type_c : natural range 0 to 255 := 0;
      node_version_c : natural range 0 to 15 := 0
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
      tlr_o : out std_ulogic;
      selected_o: out std_ulogic;
      capture_o : out std_ulogic;
      shift_o   : out std_ulogic;
      update_o  : out std_ulogic;
      run_o  : out std_ulogic;
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
      tlr_o  : out std_ulogic;
      run_o  : out std_ulogic;
      
      data_o     : out std_ulogic_vector(width_c-1 downto 0);
      update_o   : out std_ulogic;

      data_i     : in std_ulogic_vector(width_c-1 downto 0);
      capture_o  : out std_ulogic
      );
  end component;
  
end package user_tap;
