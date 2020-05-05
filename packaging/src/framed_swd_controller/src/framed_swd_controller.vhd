library ieee;
use ieee.std_logic_1164.all;

library nsl_coresight;

entity framed_swd_controller is
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

    swclk : out std_logic;
    swdio_i : in std_logic;
    swdio_t : out std_logic;
    swdio_o : out std_logic
    );
end entity;

architecture rtl of framed_swd_controller is

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

  attribute X_INTERFACE_INFO of swclk   : signal is "nsl:interface:swd:1.0 swd clk";
  attribute X_INTERFACE_INFO of swdio_t : signal is "nsl:interface:swd:1.0 swd dio_t";
  attribute X_INTERFACE_INFO of swdio_o : signal is "nsl:interface:swd:1.0 swd dio_o";
  attribute X_INTERFACE_INFO of swdio_i : signal is "nsl:interface:swd:1.0 swd dio_i";

  signal rsp_data : std_ulogic_vector(7 downto 0);
  signal dioen : std_ulogic;
  
begin

  controller: nsl_coresight.transactor.dp_framed_transactor
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

      swd_o.clk => swclk,
      swd_o.dio.output => dioen,
      swd_o.dio.v => swdio_o,
      swd_i.dio => swdio_i
      );

  swdio_t <= not dioen;
  framed_rsp_data <= std_logic_vector(rsp_data);
  
end;
