library ieee;
use ieee.std_logic_1164.all;

library nsl, signalling;

entity framed_i2c_controller is
  port(
    clock : in std_logic;
    resetn : in std_logic;

    framed_cmd_data : in std_logic_vector(7 downto 0);
    framed_cmd_last : in std_logic;
    framed_cmd_valid : in std_logic;
    framed_cmd_ready : out std_logic;
    framed_rsp_data : out std_logic_vector(7 downto 0);
    framed_rsp_last : out std_logic;
    framed_rsp_valid : out std_logic;
    framed_rsp_ready : in std_logic;

    i2c_sda_i : in std_logic;
    i2c_sda_o : out std_logic;
    i2c_sda_t : out std_logic;
    i2c_scl_i : in std_logic;
    i2c_scl_o : out std_logic;
    i2c_scl_t : out std_logic
    );
end entity;

architecture rtl of framed_i2c_controller is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_PARAMETER of clock : signal is "ASSOCIATED_BUSIF framed, ASSOCIATED_RESET resetn";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of framed_cmd_ready : signal is "nsl:interface:framed:1.0 framed req_ready";
  attribute X_INTERFACE_INFO of framed_cmd_valid : signal is "nsl:interface:framed:1.0 framed req_valid";
  attribute X_INTERFACE_INFO of framed_cmd_last  : signal is "nsl:interface:framed:1.0 framed req_last";
  attribute X_INTERFACE_INFO of framed_cmd_data  : signal is "nsl:interface:framed:1.0 framed req_data";
  attribute X_INTERFACE_INFO of framed_rsp_ready : signal is "nsl:interface:framed:1.0 framed rsp_ready";
  attribute X_INTERFACE_INFO of framed_rsp_valid : signal is "nsl:interface:framed:1.0 framed rsp_valid";
  attribute X_INTERFACE_INFO of framed_rsp_last  : signal is "nsl:interface:framed:1.0 framed rsp_last";
  attribute X_INTERFACE_INFO of framed_rsp_data  : signal is "nsl:interface:framed:1.0 framed rsp_data";

  attribute X_INTERFACE_INFO of i2c_sda_i : signal is "xilinx.com:interface:iic:1.0 i2c SDA_I";
  attribute X_INTERFACE_INFO of i2c_sda_o : signal is "xilinx.com:interface:iic:1.0 i2c SDA_O";
  attribute X_INTERFACE_INFO of i2c_sda_t : signal is "xilinx.com:interface:iic:1.0 i2c SDA_T";
  attribute X_INTERFACE_INFO of i2c_scl_i : signal is "xilinx.com:interface:iic:1.0 i2c SCL_I";
  attribute X_INTERFACE_INFO of i2c_scl_o : signal is "xilinx.com:interface:iic:1.0 i2c SCL_O";
  attribute X_INTERFACE_INFO of i2c_scl_t : signal is "xilinx.com:interface:iic:1.0 i2c SCL_T";

  signal s_i2c_o : signalling.i2c.i2c_o;
  signal s_i2c_i : signalling.i2c.i2c_i;
  signal rsp_data : std_ulogic_vector(7 downto 0);
  
begin

  controller: nsl.i2c.i2c_framed_ctrl
    port map(
      p_resetn => resetn,
      p_clk => clock,

      p_cmd_val.valid => framed_cmd_valid,
      p_cmd_val.data => std_ulogic_vector(framed_cmd_data),
      p_cmd_val.last => framed_cmd_last,
      p_cmd_ack.ready => framed_cmd_ready,
      p_rsp_val.valid => framed_rsp_valid,
      p_rsp_val.data => rsp_data,
      p_rsp_val.last => framed_rsp_last,
      p_rsp_ack.ready => framed_rsp_ready,

      p_i2c_o => s_i2c_o,
      p_i2c_i => s_i2c_i
      );

  framed_rsp_data <= std_logic_vector(rsp_data);
  
  i2c_scl_t <= not s_i2c_o.scl.drain;
  i2c_sda_t <= not s_i2c_o.sda.drain;
  i2c_scl_o <= '0';
  i2c_sda_o <= '0';
  s_i2c_i.scl.v <= i2c_scl_i;
  s_i2c_i.sda.v <= i2c_sda_i;
  
end;
