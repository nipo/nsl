library ieee;
use ieee.std_logic_1164.all;

library nsl_jtag;

entity framed_jtag_controller is
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

    jtag_tck_o : out std_logic;
    jtag_tdi_o : out std_logic;
    jtag_tdo_i : in std_logic;
    jtag_tms_o : out std_logic
    );
end entity;

architecture rtl of framed_jtag_controller is

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

  attribute X_INTERFACE_INFO of jtag_tck_o : signal is "xilinx.com:interface:jtag:2.0 jtag TCK";
  attribute X_INTERFACE_INFO of jtag_tms_o : signal is "xilinx.com:interface:jtag:2.0 jtag TMS";
  attribute X_INTERFACE_INFO of jtag_tdi_o : signal is "xilinx.com:interface:jtag:2.0 jtag TDI";
  attribute X_INTERFACE_INFO of jtag_tdo_i : signal is "xilinx.com:interface:jtag:2.0 jtag TDO";

  signal rsp_data : std_ulogic_vector(7 downto 0);
  
begin

  controller: nsl_jtag.transactor.framed_ate
    port map(
      reset_n_i => resetn,
      clock_i => clock,

      cmd_i.valid => framed_cmd_valid,
      cmd_i.data => std_ulogic_vector(framed_cmd_data),
      cmd_i.last => framed_cmd_last,
      cmd_o.ready => framed_cmd_ready,
      rsp_o.valid => framed_rsp_valid,
      rsp_o.data => rsp_data,
      rsp_o.last => framed_rsp_last,
      rsp_i.ready => framed_rsp_ready,

      jtag_o.tck => jtag_tck_o,
      jtag_o.tms => jtag_tms_o,
      jtag_o.tdi => jtag_tdi_o,
      jtag_o.trst => open,
      jtag_i.tdo => jtag_tdo_i,
      jtag_i.rtck => '0'
      );

  framed_rsp_data <= std_logic_vector(rsp_data);
  
end;
