library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_inet.vlan.all;

-- Vivado IP wrapper for nsl_inet.vlan.vlan_path_router.
--
-- IP-XACT cannot express record ports, arrays of records, or
-- unconstrained array generics, so this layer presents the same design
-- with flat std_logic ports and scalar parameters:
--
--   committed req/ack  ->  one AXI4-Stream interface (tdata, tvalid,
--                          tlast, tready)
--   committed vectors  ->  8 enumerated interfaces per direction
--   vlan_id_c          ->  vlan_count_c plus vlan_id_0_c .. vlan_id_7_c
--
-- Every interface carries committed frames: frame bytes, then one
-- status byte with tlast, bit 0 set when the frame is valid. The
-- rx_eth_vlan/tx_eth_vlan pair is the tagged layer-1 link, FCS
-- included; rx_eth_routed_N/tx_eth_routed_N carry untagged frames, with
-- an FCS only when routed_has_fcs_c is set (to plug a layer-1 driver
-- such as RMII or SGMII straight onto a pipe).
--
-- Interfaces beyond vlan_count_c are tied off here and hidden in the
-- customisation GUI by ports.tcl.

entity vlan_path_router_ip_top is
  generic(
    -- Active VLAN pipes.  Only vlan_id_0_c .. vlan_id_(vlan_count_c-1)_c
    -- are used; the remaining interfaces are tied off.
    vlan_count_c : natural range 1 to 8 := 1;
    -- Untagged frames belong to this VID.  0 is reserved by 802.1Q, so
    -- the default drops untagged frames.
    native_vlan_id_c : natural range 0 to 4095 := 0;
    vlan_id_0_c : natural range 0 to 4095 := 0;
    vlan_id_1_c : natural range 0 to 4095 := 0;
    vlan_id_2_c : natural range 0 to 4095 := 0;
    vlan_id_3_c : natural range 0 to 4095 := 0;
    vlan_id_4_c : natural range 0 to 4095 := 0;
    vlan_id_5_c : natural range 0 to 4095 := 0;
    vlan_id_6_c : natural range 0 to 4095 := 0;
    vlan_id_7_c : natural range 0 to 4095 := 0;
    -- Per-VLAN pipes in layer-1 format: FCS appended (and frames padded
    -- to 64 bytes) leaving through a pipe, FCS checked and stripped
    -- entering through one.
    routed_has_fcs_c : boolean := false
    );
  port(
    reset_n_i : in std_logic;
    clock_i   : in std_logic;

    -- Tagged layer-1 committed link, FCS present.
    rx_eth_vlan_tdata  : in  std_logic_vector(7 downto 0);
    rx_eth_vlan_tvalid : in  std_logic;
    rx_eth_vlan_tlast  : in  std_logic;
    rx_eth_vlan_tready : out std_logic;

    tx_eth_vlan_tdata  : out std_logic_vector(7 downto 0);
    tx_eth_vlan_tvalid : out std_logic;
    tx_eth_vlan_tlast  : out std_logic;
    tx_eth_vlan_tready : in  std_logic;

    rx_eth_routed_0_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_0_tvalid : out std_logic;
    rx_eth_routed_0_tlast  : out std_logic;
    rx_eth_routed_0_tready : in  std_logic;
    tx_eth_routed_0_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_0_tvalid : in  std_logic;
    tx_eth_routed_0_tlast  : in  std_logic;
    tx_eth_routed_0_tready : out std_logic;

    rx_eth_routed_1_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_1_tvalid : out std_logic;
    rx_eth_routed_1_tlast  : out std_logic;
    rx_eth_routed_1_tready : in  std_logic;
    tx_eth_routed_1_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_1_tvalid : in  std_logic;
    tx_eth_routed_1_tlast  : in  std_logic;
    tx_eth_routed_1_tready : out std_logic;

    rx_eth_routed_2_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_2_tvalid : out std_logic;
    rx_eth_routed_2_tlast  : out std_logic;
    rx_eth_routed_2_tready : in  std_logic;
    tx_eth_routed_2_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_2_tvalid : in  std_logic;
    tx_eth_routed_2_tlast  : in  std_logic;
    tx_eth_routed_2_tready : out std_logic;

    rx_eth_routed_3_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_3_tvalid : out std_logic;
    rx_eth_routed_3_tlast  : out std_logic;
    rx_eth_routed_3_tready : in  std_logic;
    tx_eth_routed_3_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_3_tvalid : in  std_logic;
    tx_eth_routed_3_tlast  : in  std_logic;
    tx_eth_routed_3_tready : out std_logic;

    rx_eth_routed_4_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_4_tvalid : out std_logic;
    rx_eth_routed_4_tlast  : out std_logic;
    rx_eth_routed_4_tready : in  std_logic;
    tx_eth_routed_4_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_4_tvalid : in  std_logic;
    tx_eth_routed_4_tlast  : in  std_logic;
    tx_eth_routed_4_tready : out std_logic;

    rx_eth_routed_5_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_5_tvalid : out std_logic;
    rx_eth_routed_5_tlast  : out std_logic;
    rx_eth_routed_5_tready : in  std_logic;
    tx_eth_routed_5_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_5_tvalid : in  std_logic;
    tx_eth_routed_5_tlast  : in  std_logic;
    tx_eth_routed_5_tready : out std_logic;

    rx_eth_routed_6_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_6_tvalid : out std_logic;
    rx_eth_routed_6_tlast  : out std_logic;
    rx_eth_routed_6_tready : in  std_logic;
    tx_eth_routed_6_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_6_tvalid : in  std_logic;
    tx_eth_routed_6_tlast  : in  std_logic;
    tx_eth_routed_6_tready : out std_logic;

    rx_eth_routed_7_tdata  : out std_logic_vector(7 downto 0);
    rx_eth_routed_7_tvalid : out std_logic;
    rx_eth_routed_7_tlast  : out std_logic;
    rx_eth_routed_7_tready : in  std_logic;
    tx_eth_routed_7_tdata  : in  std_logic_vector(7 downto 0);
    tx_eth_routed_7_tvalid : in  std_logic;
    tx_eth_routed_7_tlast  : in  std_logic;
    tx_eth_routed_7_tready : out std_logic
    );
end entity;

architecture beh of vlan_path_router_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock_i : signal is "xilinx.com:signal:clock:1.0 clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of clock_i : signal is "ASSOCIATED_BUSIF rx_eth_vlan:tx_eth_vlan:rx_eth_routed_0:rx_eth_routed_1:rx_eth_routed_2:rx_eth_routed_3:rx_eth_routed_4:rx_eth_routed_5:rx_eth_routed_6:rx_eth_routed_7:tx_eth_routed_0:tx_eth_routed_1:tx_eth_routed_2:tx_eth_routed_3:tx_eth_routed_4:tx_eth_routed_5:tx_eth_routed_6:tx_eth_routed_7, ASSOCIATED_RESET reset_n_i";

  attribute X_INTERFACE_INFO of rx_eth_vlan_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_vlan TDATA";
  attribute X_INTERFACE_INFO of rx_eth_vlan_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_vlan TVALID";
  attribute X_INTERFACE_INFO of rx_eth_vlan_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_vlan TLAST";
  attribute X_INTERFACE_INFO of rx_eth_vlan_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_vlan TREADY";
  attribute X_INTERFACE_INFO of tx_eth_vlan_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_vlan TDATA";
  attribute X_INTERFACE_INFO of tx_eth_vlan_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_vlan TVALID";
  attribute X_INTERFACE_INFO of tx_eth_vlan_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_vlan TLAST";
  attribute X_INTERFACE_INFO of tx_eth_vlan_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_vlan TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_0_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_0 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_0_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_0 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_0_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_0 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_0_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_0 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_1_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_1 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_1_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_1 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_1_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_1 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_1_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_1 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_2_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_2 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_2_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_2 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_2_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_2 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_2_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_2 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_3_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_3 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_3_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_3 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_3_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_3 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_3_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_3 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_4_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_4 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_4_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_4 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_4_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_4 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_4_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_4 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_5_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_5 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_5_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_5 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_5_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_5 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_5_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_5 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_6_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_6 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_6_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_6 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_6_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_6 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_6_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_6 TREADY";
  attribute X_INTERFACE_INFO of rx_eth_routed_7_tdata : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_7 TDATA";
  attribute X_INTERFACE_INFO of rx_eth_routed_7_tvalid : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_7 TVALID";
  attribute X_INTERFACE_INFO of rx_eth_routed_7_tlast : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_7 TLAST";
  attribute X_INTERFACE_INFO of rx_eth_routed_7_tready : signal is "xilinx.com:interface:axis:1.0 rx_eth_routed_7 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_0_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_0 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_0_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_0 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_0_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_0 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_0_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_0 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_1_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_1 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_1_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_1 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_1_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_1 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_1_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_1 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_2_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_2 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_2_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_2 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_2_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_2 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_2_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_2 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_3_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_3 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_3_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_3 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_3_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_3 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_3_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_3 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_4_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_4 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_4_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_4 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_4_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_4 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_4_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_4 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_5_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_5 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_5_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_5 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_5_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_5 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_5_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_5 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_6_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_6 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_6_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_6 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_6_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_6 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_6_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_6 TREADY";
  attribute X_INTERFACE_INFO of tx_eth_routed_7_tdata : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_7 TDATA";
  attribute X_INTERFACE_INFO of tx_eth_routed_7_tvalid : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_7 TVALID";
  attribute X_INTERFACE_INFO of tx_eth_routed_7_tlast : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_7 TLAST";
  attribute X_INTERFACE_INFO of tx_eth_routed_7_tready : signal is "xilinx.com:interface:axis:1.0 tx_eth_routed_7 TREADY";

  function vlan_ids(n : natural;
                    v0, v1, v2, v3, v4, v5, v6, v7 : natural) return vlan_id_vector
  is
    constant all_c : vlan_id_vector(0 to 7) := (v0, v1, v2, v3, v4, v5, v6, v7);
    variable r : vlan_id_vector(0 to n-1);
  begin
    for i in 0 to n-1 loop
      r(i) := all_c(i);
    end loop;
    return r;
  end function;

  constant vids_c : vlan_id_vector(0 to vlan_count_c-1)
    := vlan_ids(vlan_count_c, vlan_id_0_c, vlan_id_1_c, vlan_id_2_c, vlan_id_3_c, vlan_id_4_c, vlan_id_5_c, vlan_id_6_c, vlan_id_7_c);

  signal rx_eth_s, tx_eth_s : committed_bus_t;
  signal rx_eth_routed_req_s : committed_req_vector(0 to vlan_count_c-1);
  signal rx_eth_routed_ack_s : committed_ack_vector(0 to vlan_count_c-1);
  signal tx_eth_routed_req_s : committed_req_vector(0 to vlan_count_c-1);
  signal tx_eth_routed_ack_s : committed_ack_vector(0 to vlan_count_c-1);

begin

  -- Flat -> record on the layer-1 side, and back.
  rx_eth_s.req <= framed_flit(data  => std_ulogic_vector(rx_eth_vlan_tdata),
                              last  => rx_eth_vlan_tlast = '1',
                              valid => rx_eth_vlan_tvalid = '1');
  rx_eth_vlan_tready <= rx_eth_s.ack.ready;

  tx_eth_vlan_tdata  <= std_logic_vector(tx_eth_s.req.data);
  tx_eth_vlan_tvalid <= tx_eth_s.req.valid;
  tx_eth_vlan_tlast  <= tx_eth_s.req.last;
  tx_eth_s.ack <= framed_accept(tx_eth_vlan_tready = '1');

  vlan_0: if vlan_count_c > 0
  generate
    rx_eth_routed_0_tdata  <= std_logic_vector(rx_eth_routed_req_s(0).data);
    rx_eth_routed_0_tvalid <= rx_eth_routed_req_s(0).valid;
    rx_eth_routed_0_tlast  <= rx_eth_routed_req_s(0).last;
    rx_eth_routed_ack_s(0) <= framed_accept(rx_eth_routed_0_tready = '1');

    tx_eth_routed_req_s(0) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_0_tdata),
                                       last  => tx_eth_routed_0_tlast = '1',
                                       valid => tx_eth_routed_0_tvalid = '1');
    tx_eth_routed_0_tready <= tx_eth_routed_ack_s(0).ready;
  end generate;

  vlan_0_off: if vlan_count_c <= 0
  generate
    rx_eth_routed_0_tdata  <= (others => '0');
    rx_eth_routed_0_tvalid <= '0';
    rx_eth_routed_0_tlast  <= '0';
    tx_eth_routed_0_tready <= '0';
  end generate;

  vlan_1: if vlan_count_c > 1
  generate
    rx_eth_routed_1_tdata  <= std_logic_vector(rx_eth_routed_req_s(1).data);
    rx_eth_routed_1_tvalid <= rx_eth_routed_req_s(1).valid;
    rx_eth_routed_1_tlast  <= rx_eth_routed_req_s(1).last;
    rx_eth_routed_ack_s(1) <= framed_accept(rx_eth_routed_1_tready = '1');

    tx_eth_routed_req_s(1) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_1_tdata),
                                       last  => tx_eth_routed_1_tlast = '1',
                                       valid => tx_eth_routed_1_tvalid = '1');
    tx_eth_routed_1_tready <= tx_eth_routed_ack_s(1).ready;
  end generate;

  vlan_1_off: if vlan_count_c <= 1
  generate
    rx_eth_routed_1_tdata  <= (others => '0');
    rx_eth_routed_1_tvalid <= '0';
    rx_eth_routed_1_tlast  <= '0';
    tx_eth_routed_1_tready <= '0';
  end generate;

  vlan_2: if vlan_count_c > 2
  generate
    rx_eth_routed_2_tdata  <= std_logic_vector(rx_eth_routed_req_s(2).data);
    rx_eth_routed_2_tvalid <= rx_eth_routed_req_s(2).valid;
    rx_eth_routed_2_tlast  <= rx_eth_routed_req_s(2).last;
    rx_eth_routed_ack_s(2) <= framed_accept(rx_eth_routed_2_tready = '1');

    tx_eth_routed_req_s(2) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_2_tdata),
                                       last  => tx_eth_routed_2_tlast = '1',
                                       valid => tx_eth_routed_2_tvalid = '1');
    tx_eth_routed_2_tready <= tx_eth_routed_ack_s(2).ready;
  end generate;

  vlan_2_off: if vlan_count_c <= 2
  generate
    rx_eth_routed_2_tdata  <= (others => '0');
    rx_eth_routed_2_tvalid <= '0';
    rx_eth_routed_2_tlast  <= '0';
    tx_eth_routed_2_tready <= '0';
  end generate;

  vlan_3: if vlan_count_c > 3
  generate
    rx_eth_routed_3_tdata  <= std_logic_vector(rx_eth_routed_req_s(3).data);
    rx_eth_routed_3_tvalid <= rx_eth_routed_req_s(3).valid;
    rx_eth_routed_3_tlast  <= rx_eth_routed_req_s(3).last;
    rx_eth_routed_ack_s(3) <= framed_accept(rx_eth_routed_3_tready = '1');

    tx_eth_routed_req_s(3) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_3_tdata),
                                       last  => tx_eth_routed_3_tlast = '1',
                                       valid => tx_eth_routed_3_tvalid = '1');
    tx_eth_routed_3_tready <= tx_eth_routed_ack_s(3).ready;
  end generate;

  vlan_3_off: if vlan_count_c <= 3
  generate
    rx_eth_routed_3_tdata  <= (others => '0');
    rx_eth_routed_3_tvalid <= '0';
    rx_eth_routed_3_tlast  <= '0';
    tx_eth_routed_3_tready <= '0';
  end generate;

  vlan_4: if vlan_count_c > 4
  generate
    rx_eth_routed_4_tdata  <= std_logic_vector(rx_eth_routed_req_s(4).data);
    rx_eth_routed_4_tvalid <= rx_eth_routed_req_s(4).valid;
    rx_eth_routed_4_tlast  <= rx_eth_routed_req_s(4).last;
    rx_eth_routed_ack_s(4) <= framed_accept(rx_eth_routed_4_tready = '1');

    tx_eth_routed_req_s(4) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_4_tdata),
                                       last  => tx_eth_routed_4_tlast = '1',
                                       valid => tx_eth_routed_4_tvalid = '1');
    tx_eth_routed_4_tready <= tx_eth_routed_ack_s(4).ready;
  end generate;

  vlan_4_off: if vlan_count_c <= 4
  generate
    rx_eth_routed_4_tdata  <= (others => '0');
    rx_eth_routed_4_tvalid <= '0';
    rx_eth_routed_4_tlast  <= '0';
    tx_eth_routed_4_tready <= '0';
  end generate;

  vlan_5: if vlan_count_c > 5
  generate
    rx_eth_routed_5_tdata  <= std_logic_vector(rx_eth_routed_req_s(5).data);
    rx_eth_routed_5_tvalid <= rx_eth_routed_req_s(5).valid;
    rx_eth_routed_5_tlast  <= rx_eth_routed_req_s(5).last;
    rx_eth_routed_ack_s(5) <= framed_accept(rx_eth_routed_5_tready = '1');

    tx_eth_routed_req_s(5) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_5_tdata),
                                       last  => tx_eth_routed_5_tlast = '1',
                                       valid => tx_eth_routed_5_tvalid = '1');
    tx_eth_routed_5_tready <= tx_eth_routed_ack_s(5).ready;
  end generate;

  vlan_5_off: if vlan_count_c <= 5
  generate
    rx_eth_routed_5_tdata  <= (others => '0');
    rx_eth_routed_5_tvalid <= '0';
    rx_eth_routed_5_tlast  <= '0';
    tx_eth_routed_5_tready <= '0';
  end generate;

  vlan_6: if vlan_count_c > 6
  generate
    rx_eth_routed_6_tdata  <= std_logic_vector(rx_eth_routed_req_s(6).data);
    rx_eth_routed_6_tvalid <= rx_eth_routed_req_s(6).valid;
    rx_eth_routed_6_tlast  <= rx_eth_routed_req_s(6).last;
    rx_eth_routed_ack_s(6) <= framed_accept(rx_eth_routed_6_tready = '1');

    tx_eth_routed_req_s(6) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_6_tdata),
                                       last  => tx_eth_routed_6_tlast = '1',
                                       valid => tx_eth_routed_6_tvalid = '1');
    tx_eth_routed_6_tready <= tx_eth_routed_ack_s(6).ready;
  end generate;

  vlan_6_off: if vlan_count_c <= 6
  generate
    rx_eth_routed_6_tdata  <= (others => '0');
    rx_eth_routed_6_tvalid <= '0';
    rx_eth_routed_6_tlast  <= '0';
    tx_eth_routed_6_tready <= '0';
  end generate;

  vlan_7: if vlan_count_c > 7
  generate
    rx_eth_routed_7_tdata  <= std_logic_vector(rx_eth_routed_req_s(7).data);
    rx_eth_routed_7_tvalid <= rx_eth_routed_req_s(7).valid;
    rx_eth_routed_7_tlast  <= rx_eth_routed_req_s(7).last;
    rx_eth_routed_ack_s(7) <= framed_accept(rx_eth_routed_7_tready = '1');

    tx_eth_routed_req_s(7) <= framed_flit(data  => std_ulogic_vector(tx_eth_routed_7_tdata),
                                       last  => tx_eth_routed_7_tlast = '1',
                                       valid => tx_eth_routed_7_tvalid = '1');
    tx_eth_routed_7_tready <= tx_eth_routed_ack_s(7).ready;
  end generate;

  vlan_7_off: if vlan_count_c <= 7
  generate
    rx_eth_routed_7_tdata  <= (others => '0');
    rx_eth_routed_7_tvalid <= '0';
    rx_eth_routed_7_tlast  <= '0';
    tx_eth_routed_7_tready <= '0';
  end generate;

  dut: nsl_inet.vlan.vlan_path_router
    generic map(
      vlan_id_c        => vids_c,
      native_vlan_id_c => native_vlan_id_c,
      routed_has_fcs_c => routed_has_fcs_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      rx_eth_vlan_i => rx_eth_s.req,
      rx_eth_vlan_o => rx_eth_s.ack,
      tx_eth_vlan_o => tx_eth_s.req,
      tx_eth_vlan_i => tx_eth_s.ack,

      rx_eth_routed_o => rx_eth_routed_req_s,
      rx_eth_routed_i => rx_eth_routed_ack_s,
      tx_eth_routed_i => tx_eth_routed_req_s,
      tx_eth_routed_o => tx_eth_routed_ack_s
      );

end architecture;
