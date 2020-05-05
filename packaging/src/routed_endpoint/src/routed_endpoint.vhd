library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

entity routed_endpoint is
  port(
    clock : in std_logic;
    resetn : in std_logic;

    routed_cmd_data : in std_logic_vector(7 downto 0);
    routed_cmd_last : in std_logic;
    routed_cmd_valid : in std_logic;
    routed_cmd_ready : out std_logic;
    routed_rsp_data : out std_logic_vector(7 downto 0);
    routed_rsp_last : out std_logic;
    routed_rsp_valid : out std_logic;
    routed_rsp_ready : in std_logic;

    framed_cmd_data : out std_logic_vector(7 downto 0);
    framed_cmd_last : out std_logic;
    framed_cmd_valid : out std_logic;
    framed_cmd_ready : in std_logic;
    framed_rsp_data : in std_logic_vector(7 downto 0);
    framed_rsp_last : in std_logic;
    framed_rsp_valid : in std_logic;
    framed_rsp_ready : out std_logic
    );
end entity;

architecture rtl of routed_endpoint is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_PARAMETER of clock : signal is "ASSOCIATED_BUSIF routed:framed, ASSOCIATED_RESET resetn";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";
  
  attribute X_INTERFACE_INFO of routed_cmd_ready : signal is "nsl:interface:routed:1.0 routed req_ready";
  attribute X_INTERFACE_INFO of routed_cmd_valid : signal is "nsl:interface:routed:1.0 routed req_valid";
  attribute X_INTERFACE_INFO of routed_cmd_last  : signal is "nsl:interface:routed:1.0 routed req_last";
  attribute X_INTERFACE_INFO of routed_cmd_data  : signal is "nsl:interface:routed:1.0 routed req_data";
  attribute X_INTERFACE_INFO of routed_rsp_ready : signal is "nsl:interface:routed:1.0 routed rsp_ready";
  attribute X_INTERFACE_INFO of routed_rsp_valid : signal is "nsl:interface:routed:1.0 routed rsp_valid";
  attribute X_INTERFACE_INFO of routed_rsp_last  : signal is "nsl:interface:routed:1.0 routed rsp_last";
  attribute X_INTERFACE_INFO of routed_rsp_data  : signal is "nsl:interface:routed:1.0 routed rsp_data";

  attribute X_INTERFACE_INFO of framed_cmd_ready : signal is "nsl:interface:framed:1.0 framed req_ready";
  attribute X_INTERFACE_INFO of framed_cmd_valid : signal is "nsl:interface:framed:1.0 framed req_valid";
  attribute X_INTERFACE_INFO of framed_cmd_last  : signal is "nsl:interface:framed:1.0 framed req_last";
  attribute X_INTERFACE_INFO of framed_cmd_data  : signal is "nsl:interface:framed:1.0 framed req_data";
  attribute X_INTERFACE_INFO of framed_rsp_ready : signal is "nsl:interface:framed:1.0 framed rsp_ready";
  attribute X_INTERFACE_INFO of framed_rsp_valid : signal is "nsl:interface:framed:1.0 framed rsp_valid";
  attribute X_INTERFACE_INFO of framed_rsp_last  : signal is "nsl:interface:framed:1.0 framed rsp_last";
  attribute X_INTERFACE_INFO of framed_rsp_data  : signal is "nsl:interface:framed:1.0 framed rsp_data";

  signal cmd_data, rsp_data : std_ulogic_vector(7 downto 0);
  
begin

  framed_cmd_data <= std_logic_vector(cmd_data);
  routed_rsp_data <= std_logic_vector(rsp_data);
  
  gateway: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => resetn,
      p_clk => clock,

      p_cmd_in_val.valid => routed_cmd_valid,
      p_cmd_in_val.data => std_ulogic_vector(routed_cmd_data),
      p_cmd_in_val.last => routed_cmd_last,
      p_cmd_in_ack.ready => routed_cmd_ready,
      p_cmd_out_val.valid => framed_cmd_valid,
      p_cmd_out_val.data => cmd_data,
      p_cmd_out_val.last => framed_cmd_last,
      p_cmd_out_ack.ready => framed_cmd_ready,

      p_rsp_in_val.valid => framed_rsp_valid,
      p_rsp_in_val.data => std_ulogic_vector(framed_rsp_data),
      p_rsp_in_val.last => framed_rsp_last,
      p_rsp_in_ack.ready => framed_rsp_ready,
      p_rsp_out_val.valid => routed_rsp_valid,
      p_rsp_out_val.data => rsp_data,
      p_rsp_out_val.last => routed_rsp_last,
      p_rsp_out_ack.ready => routed_rsp_ready
      );

end;
