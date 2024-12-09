library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_uart, nsl_line_coding, nsl_bnoc;

entity framed_uart_trx is
  generic(
    clock_hz : integer := 100e6;
    baudrate : integer := 1e6
    );
  port(
    aclk : in std_logic;
    aresetn : in std_logic;
    
    axis_m_tdata : out std_logic_vector (7 downto 0 );
    axis_m_tlast : out std_logic;
    axis_m_tready : in std_logic;
    axis_m_tvalid : out std_logic;

    axis_s_tdata : in std_logic_vector (7 downto 0 );
    axis_s_tlast : in std_logic;
    axis_s_tready : out std_logic;
    axis_s_tvalid : in std_logic;

    uart_tx : out std_logic;
    uart_rx : in std_logic
    );
end entity;

architecture rtl of framed_uart_trx is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF axis_m:axis_s, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of axis_m_tready : signal is "xilinx.com:interface:axis:1.0 axis_m TREADY";
  attribute X_INTERFACE_INFO of axis_m_tvalid : signal is "xilinx.com:interface:axis:1.0 axis_m TVALID";
  attribute X_INTERFACE_INFO of axis_m_tlast  : signal is "xilinx.com:interface:axis:1.0 axis_m TLAST";
  attribute X_INTERFACE_INFO of axis_m_tdata  : signal is "xilinx.com:interface:axis:1.0 axis_m TDATA";
  attribute X_INTERFACE_PARAMETER of axis_m_tdata : signal is "TDATA_NUM_BYTES 1";
  attribute X_INTERFACE_INFO of axis_s_tready : signal is "xilinx.com:interface:axis:1.0 axis_s TREADY";
  attribute X_INTERFACE_INFO of axis_s_tvalid : signal is "xilinx.com:interface:axis:1.0 axis_s TVALID";
  attribute X_INTERFACE_INFO of axis_s_tlast  : signal is "xilinx.com:interface:axis:1.0 axis_s TLAST";
  attribute X_INTERFACE_INFO of axis_s_tdata  : signal is "xilinx.com:interface:axis:1.0 axis_s TDATA";
  attribute X_INTERFACE_PARAMETER of axis_s_tdata : signal is "TDATA_NUM_BYTES 1";

  attribute X_INTERFACE_INFO of uart_rx : signal is "xilinx.com:interface:uart:1.0 uart RxD";
  attribute X_INTERFACE_INFO of uart_tx : signal is "xilinx.com:interface:uart:1.0 uart TxD";

  constant divisor_edge_c : unsigned := nsl_math.arith.to_unsigned_auto(clock_hz / baudrate - 1);
  signal uart_rx_s, uart_tx_s: nsl_bnoc.pipe.pipe_bus_t;
  signal uart_hs_rx_s, uart_hs_tx_s: nsl_bnoc.pipe.pipe_bus_t;
  signal hdlc_rx_s, hdlc_tx_s: nsl_bnoc.committed.committed_bus_t;
  signal flow_peer_ready_s, flow_local_ready_s: std_ulogic;
  signal m_tdata, s_tdata: std_ulogic_vector(7 downto 0);
  
begin
  
  uart: nsl_uart.transactor.uart8
    port map(
      reset_n_i => aresetn,
      clock_i => aclk,

      divisor_i => divisor_edge_c,

      tx_o => uart_tx,
      rx_i => uart_rx,

      tx_data_i => uart_tx_s.req,
      tx_data_o => uart_tx_s.ack,

      rx_data_i => uart_rx_s.ack,
      rx_data_o => uart_rx_s.req
      );

  rx_hs: nsl_uart.flow_control.xonxoff_rx
    port map(
      reset_n_i => aresetn,
      clock_i => aclk,

      peer_ready_o => flow_peer_ready_s,
      rx_ready_o => flow_local_ready_s,

      serdes_i => uart_rx_s.req,
      serdes_o => uart_rx_s.ack,

      rx_o => uart_hs_rx_s.req,
      rx_i => uart_hs_rx_s.ack
      );

  tx_hs: nsl_uart.flow_control.xonxoff_tx
    port map(
      reset_n_i => aresetn,
      clock_i => aclk,

      can_transmit_i => flow_peer_ready_s,
      can_receive_i => flow_local_ready_s,

      tx_i => uart_hs_tx_s.req,
      tx_o => uart_hs_tx_s.ack,

      serdes_o => uart_tx_s.req,
      serdes_i => uart_tx_s.ack
      );

  hdlc_unframer: nsl_line_coding.hdlc.hdlc_unframer
    port map(
      reset_n_i => aresetn,
      clock_i => aclk,

      hdlc_i => uart_hs_rx_s.req,
      hdlc_o => uart_hs_rx_s.ack,

      frame_o.valid => axis_m_tvalid,
      frame_o.last => axis_m_tlast,
      frame_o.data => m_tdata,
      frame_i.ready => axis_m_tready
      );
  axis_m_tdata <= std_logic_vector(m_tdata);

  hdlc_framer: nsl_line_coding.hdlc.hdlc_framer
    port map(
      reset_n_i => aresetn,
      clock_i => aclk,

      frame_i.valid => axis_s_tvalid,
      frame_i.last => axis_s_tlast,
      frame_i.data => s_tdata,
      frame_o.ready => axis_s_tready,

      hdlc_o => uart_hs_tx_s.req,
      hdlc_i => uart_hs_tx_s.ack
      );
  s_tdata <= std_ulogic_vector(axis_s_tdata);

end;
