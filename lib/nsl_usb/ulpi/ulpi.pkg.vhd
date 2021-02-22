library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data;
use nsl_usb.utmi.all;
use nsl_usb.usb.all;
use nsl_data.bytestream.all;

package ulpi is

  type ulpi8_link2phy is
  record
    data : byte;
    stp : std_ulogic;
    reset : std_ulogic;
  end record;

  type ulpi8_phy2link is
  record
    data : byte;
    clock : std_ulogic;
    dir : std_ulogic;
    nxt : std_ulogic;
  end record;

  type ulpi8 is
  record
    phy2link: ulpi8_phy2link;
    link2phy: ulpi8_link2phy;
  end record;

  subtype ulpi_op_t is unsigned(1 downto 0);
  constant ULPI_OP_SPECIAL   : ulpi_op_t := "00";
  constant ULPI_OP_TRANSMIT  : ulpi_op_t := "01";
  constant ULPI_OP_REG_WRITE : ulpi_op_t := "10";
  constant ULPI_OP_REG_READ  : ulpi_op_t := "11";
  
  subtype ulpi_reg_addr_t is unsigned(5 downto 0);
  subtype ulpi_reg8_addr_t is unsigned(7 downto 0);

  constant ULPI_REG_VID_LOW              : ulpi_reg_addr_t := "000000";
  constant ULPI_REG_VID_HIGH             : ulpi_reg_addr_t := "000001";
  constant ULPI_REG_PID_LOW              : ulpi_reg_addr_t := "000010";
  constant ULPI_REG_PID_HIGH             : ulpi_reg_addr_t := "000011";
  -- [1:0] xcvrselect
  -- [2]   termselect
  -- [4:3] opmode
  -- [5]   reset
  -- [6]   suspendm
  -- [7]   rsvd
  constant ULPI_REG_FUNC_CTRL_WRITE      : ulpi_reg_addr_t := "000100";
  constant ULPI_REG_FUNC_CTRL_SET        : ulpi_reg_addr_t := "000101";
  constant ULPI_REG_FUNC_CTRL_CLR        : ulpi_reg_addr_t := "000110";
  constant ULPI_REG_INTF_CTRL_WRITE      : ulpi_reg_addr_t := "000111";
  constant ULPI_REG_INTF_CTRL_SET        : ulpi_reg_addr_t := "001000";
  constant ULPI_REG_INTF_CTRL_CLR        : ulpi_reg_addr_t := "001001";
  -- [0]   idpullup
  -- [1]   dppulldown
  -- [2]   dmpulldown
  -- [3]   dischrgvbus
  -- [4]   chrgvbus
  -- [5]   drvvbus
  -- [6]   drvvbus_external
  -- [7]   useexternalvbusindicator
  constant ULPI_REG_OTG_CTRL_WRITE       : ulpi_reg_addr_t := "001010";
  constant ULPI_REG_OTG_CTRL_SET         : ulpi_reg_addr_t := "001011";
  constant ULPI_REG_OTG_CTRL_CLR         : ulpi_reg_addr_t := "001100";
  constant ULPI_REG_IRQ_EN_RISING_WRITE  : ulpi_reg_addr_t := "001101";
  constant ULPI_REG_IRQ_EN_RISING_SET    : ulpi_reg_addr_t := "001110";
  constant ULPI_REG_IRQ_EN_RISING_CLR    : ulpi_reg_addr_t := "001111";
  constant ULPI_REG_IRQ_EN_FALLING_WRITE : ulpi_reg_addr_t := "010000";
  constant ULPI_REG_IRQ_EN_FALLING_SET   : ulpi_reg_addr_t := "010001";
  constant ULPI_REG_IRQ_EN_FALLING_CLR   : ulpi_reg_addr_t := "010010";
  constant ULPI_REG_IRQ_STATUS           : ulpi_reg_addr_t := "010011";
  constant ULPI_REG_IRQ_LATCH            : ulpi_reg_addr_t := "010100";
  constant ULPI_REG_DEBUG                : ulpi_reg_addr_t := "010101";
  constant ULPI_REG_SCRATCH_WRITE        : ulpi_reg_addr_t := "010110";
  constant ULPI_REG_SCRATCH_SET          : ulpi_reg_addr_t := "010111";
  constant ULPI_REG_SCRATCH_CLR          : ulpi_reg_addr_t := "011000";
  constant ULPI_REG_EXT                  : ulpi_reg_addr_t := "101111";

  -- USB3340-specific registers
  -- Seems shared with many other SMSC/Microchip products
  constant ULPI_USB33XX_USB_IO_WRITE     : ulpi_reg_addr_t := "111001";
  constant ULPI_USB33XX_USB_IO_SET       : ulpi_reg_addr_t := "111010";
  constant ULPI_USB33XX_USB_IO_CLR       : ulpi_reg_addr_t := "111011";
  -- [0]   Reserved
  -- [1]   SwapDpDm
  -- [3:2] UartRegOut
  -- [4]   ChargerPullupEnDp
  -- [5]   ChargerPullupEnDm
  -- [7:6] UsbRegOut

  -- TUSB1210-specific registers
  constant ULPI_TUSB1210_VENDOR_SPECIFIC2_WRITE     : ulpi_reg8_addr_t := "10000000";
  constant ULPI_TUSB1210_VENDOR_SPECIFIC2_SET       : ulpi_reg8_addr_t := "10000001";
  constant ULPI_TUSB1210_VENDOR_SPECIFIC2_CLR       : ulpi_reg8_addr_t := "10000010";
  -- [3:0] IHSTx, default = 1
  -- [5:4] ZHSDrv, default = 0
  -- [6]   Polarity (1 by default, 0 = swap)
  -- [7]   Spare, default = 0

  type dpdm_swap_t is (
    DPDM_SWAP_NONE,
    DPDM_SWAP_SMSC,
    DPDM_SWAP_TI
    );

  -- This function is not limited to SMSC, it may be enhanced to support Ti
  -- model list once we add support for their register map, for instance.
  function ulpi_phy_dpdm_swap_method(model: string) return dpdm_swap_t;

  function ulpi_cmd_reg_write(reg : ulpi_reg_addr_t) return byte;
  function ulpi_cmd_transmit(pid : pid_t) return byte;
  function ulpi_cmd_noop return byte;
  
  component ulpi8_line_driver is
    generic(
      reset_active_c : std_ulogic := '1'
      );
    port(
      data_io: inout std_logic_vector(7 downto 0);
      dir_i: in std_ulogic;
      nxt_i: in std_ulogic;
      stp_o: out std_ulogic;
      reset_o: out std_ulogic;
      clock_i: in std_ulogic;

      ulpi_tap_o : out std_ulogic_vector(11 downto 0);

      bus_o : out ulpi8_phy2link;
      bus_i : in ulpi8_link2phy
      );
  end component;

  component ulpi8_line_driver_clock_master is
    generic(
      reset_active_c : std_ulogic := '1'
      );
    port(
      clock_i : in std_ulogic;

      data_io: inout std_logic_vector(7 downto 0);
      dir_i: in std_ulogic;
      nxt_i: in std_ulogic;
      stp_o: out std_ulogic;
      reset_o: out std_ulogic;
      clock_o: out std_ulogic;

      ulpi_tap_o : out std_ulogic_vector(11 downto 0);

      bus_o : out ulpi8_phy2link;
      bus_i : in ulpi8_link2phy
      );
  end component;

  component utmi8_ulpi8_converter is
    generic(
      -- Sets register layout for some Phy-Specific registers.
      -- DP/DM swap option is one of them.
      -- Supported values: GENERIC, USB3340.
      phy_model_c : string := "GENERIC";
      -- Supported if phy_model_c is USB3340
      dpdm_swap_c : boolean := false
      );
    port(
      reset_n_i : in std_ulogic;

      ulpi_i : in ulpi8_phy2link;
      ulpi_o : out ulpi8_link2phy;

      utmi_data_i: in utmi_data8_sie2phy;
      utmi_data_o: out utmi_data8_phy2sie;
      utmi_system_i: in utmi_system_sie2phy;
      utmi_system_o: out utmi_system_phy2sie
      );
  end component;

end package ulpi;

package body ulpi is

  use nsl_data.text.strfind;

  function ulpi_cmd_reg_write(reg : ulpi_reg_addr_t) return byte
  is
    variable ret : std_ulogic_vector(7 downto 0);
  begin
    ret := (others => '0');
    ret(7 downto 6) := std_ulogic_vector(ULPI_OP_REG_WRITE);
    ret(5 downto 0) := std_ulogic_vector(reg);

    return byte(ret);
  end function;
  
  function ulpi_cmd_transmit(pid : pid_t) return byte
  is
    variable ret : std_ulogic_vector(7 downto 0);
  begin
    ret := (others => '0');
    ret(7 downto 6) := std_ulogic_vector(ULPI_OP_TRANSMIT);
    ret(3 downto 0) := std_ulogic_vector(pid);

    return byte(ret);
  end function;
  
  function ulpi_cmd_noop return byte
  is
    variable ret : std_ulogic_vector(7 downto 0);
  begin
    ret := (others => '0');
    ret(7 downto 6) := std_ulogic_vector(ULPI_OP_SPECIAL);
    return byte(ret);
  end function;

  function ulpi_phy_dpdm_swap_method(model: string) return dpdm_swap_t
  is
  begin
    if strfind("USB3340,USB83340", model, ',') then
      return DPDM_SWAP_SMSC;
    end if;
    if strfind("TUSB1210", model, ',') then
      return DPDM_SWAP_TI;
    end if;
    return DPDM_SWAP_NONE;
  end function;

end package body;
