library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_data;
use nsl_data.bytestream.all;

package utmi is

  type utmi_op_mode_t is (
    UTMI_OP_MODE_NORMAL,
    UTMI_OP_MODE_NON_DRIVING,
    UTMI_OP_MODE_STUFF_DIS,
    UTMI_OP_MODE_RESERVED
    );

  type utmi_mode_t is (
    UTMI_MODE_HS,
    UTMI_MODE_FS
    );

  function to_logic(op_mode: utmi_op_mode_t) return std_ulogic_vector;
  function to_logic(mode: utmi_mode_t) return std_ulogic;
  function to_op_mode(data: std_ulogic_vector(1 downto 0)) return utmi_op_mode_t;
  function to_mode(data: std_ulogic) return utmi_mode_t;
  
  type utmi_system_sie2phy is
  record
    xcvr_select : utmi_mode_t;
    term_select : utmi_mode_t;
    suspend : boolean; -- active high
    op_mode : utmi_op_mode_t;
    reset : std_ulogic; -- active high
  end record;

  type utmi_system_phy2sie is
  record
    clock : std_ulogic;
    line_state : nsl_usb.usb.usb_symbol_t;
  end record;

  type utmi_data8_sie2phy is
  record
    data : byte;
    tx_valid : std_ulogic;
  end record;

  type utmi_data8_phy2sie is
  record
    tx_ready : std_ulogic;

    data : byte;
    rx_valid : std_ulogic;
    rx_active : std_ulogic;
    rx_error : std_ulogic;
  end record;

end package utmi;

package body utmi is

  function to_logic(op_mode: utmi_op_mode_t) return std_ulogic_vector
  is
  begin
    case op_mode is
      when UTMI_OP_MODE_NORMAL => return "00";
      when UTMI_OP_MODE_NON_DRIVING => return "01";
      when UTMI_OP_MODE_STUFF_DIS => return "10";
      when UTMI_OP_MODE_RESERVED => return "11";
    end case;
  end function;

  function to_logic(mode: utmi_mode_t) return std_ulogic
  is
  begin
    if mode = UTMI_MODE_HS then
      return '0';
    else
      return '1';
    end if;
  end function;

  function to_op_mode(data: std_ulogic_vector(1 downto 0)) return utmi_op_mode_t
  is
  begin
    case data is
      when "00" => return UTMI_OP_MODE_NORMAL;
      when "01" => return UTMI_OP_MODE_NON_DRIVING;
      when "10" => return UTMI_OP_MODE_STUFF_DIS;
      when others => return UTMI_OP_MODE_RESERVED;
    end case;
  end function;

  function to_mode(data: std_ulogic) return utmi_mode_t
  is
  begin
    if data = '1' then
      return UTMI_MODE_FS;
    else
      return UTMI_MODE_HS;
    end if;
  end function;

end package body;
