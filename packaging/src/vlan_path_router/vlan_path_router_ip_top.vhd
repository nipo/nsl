library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_inet, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_inet.vlan.all;
use nsl_logic.bool.all;

-- Vivado IP wrapper for nsl_inet.vlan.vlan_path_router.
--
-- IP-XACT cannot express record ports, arrays of records, or
-- unconstrained array generics, so this layer presents the same design
-- with flat std_logic ports and scalar parameters:
--
--   committed_bus_t  ->  two AXI4-Stream interfaces
--   master/slave_vector -> 8 enumerated AXI4-Stream interfaces per way
--   vlan_id_c        ->  vlan_count_c plus vlan_id_0_c .. vlan_id_7_c
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
    vlan_id_7_c : natural range 0 to 4095 := 0
    );
  port(
    reset_n_i : in std_logic;
    clock_i   : in std_logic;

    -- Layer-1 committed link, FCS present, byte wide with tlast.
    l1_i_tdata  : in  std_logic_vector(7 downto 0);
    l1_i_tvalid : in  std_logic;
    l1_i_tlast  : in  std_logic;
    l1_i_tready : out std_logic;

    l1_o_tdata  : out std_logic_vector(7 downto 0);
    l1_o_tvalid : out std_logic;
    l1_o_tlast  : out std_logic;
    l1_o_tready : in  std_logic;

    routed_tx_0_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_0_tvalid : out std_logic;
    routed_tx_0_tlast  : out std_logic;
    routed_tx_0_tready : in  std_logic;
    routed_rx_0_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_0_tvalid : in  std_logic;
    routed_rx_0_tlast  : in  std_logic;
    routed_rx_0_tready : out std_logic;

    routed_tx_1_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_1_tvalid : out std_logic;
    routed_tx_1_tlast  : out std_logic;
    routed_tx_1_tready : in  std_logic;
    routed_rx_1_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_1_tvalid : in  std_logic;
    routed_rx_1_tlast  : in  std_logic;
    routed_rx_1_tready : out std_logic;

    routed_tx_2_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_2_tvalid : out std_logic;
    routed_tx_2_tlast  : out std_logic;
    routed_tx_2_tready : in  std_logic;
    routed_rx_2_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_2_tvalid : in  std_logic;
    routed_rx_2_tlast  : in  std_logic;
    routed_rx_2_tready : out std_logic;

    routed_tx_3_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_3_tvalid : out std_logic;
    routed_tx_3_tlast  : out std_logic;
    routed_tx_3_tready : in  std_logic;
    routed_rx_3_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_3_tvalid : in  std_logic;
    routed_rx_3_tlast  : in  std_logic;
    routed_rx_3_tready : out std_logic;

    routed_tx_4_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_4_tvalid : out std_logic;
    routed_tx_4_tlast  : out std_logic;
    routed_tx_4_tready : in  std_logic;
    routed_rx_4_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_4_tvalid : in  std_logic;
    routed_rx_4_tlast  : in  std_logic;
    routed_rx_4_tready : out std_logic;

    routed_tx_5_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_5_tvalid : out std_logic;
    routed_tx_5_tlast  : out std_logic;
    routed_tx_5_tready : in  std_logic;
    routed_rx_5_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_5_tvalid : in  std_logic;
    routed_rx_5_tlast  : in  std_logic;
    routed_rx_5_tready : out std_logic;

    routed_tx_6_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_6_tvalid : out std_logic;
    routed_tx_6_tlast  : out std_logic;
    routed_tx_6_tready : in  std_logic;
    routed_rx_6_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_6_tvalid : in  std_logic;
    routed_rx_6_tlast  : in  std_logic;
    routed_rx_6_tready : out std_logic;

    routed_tx_7_tdata  : out std_logic_vector(7 downto 0);
    routed_tx_7_tvalid : out std_logic;
    routed_tx_7_tlast  : out std_logic;
    routed_tx_7_tready : in  std_logic;
    routed_rx_7_tdata  : in  std_logic_vector(7 downto 0);
    routed_rx_7_tvalid : in  std_logic;
    routed_rx_7_tlast  : in  std_logic;
    routed_rx_7_tready : out std_logic
    );
end entity;

architecture beh of vlan_path_router_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock_i : signal is "xilinx.com:signal:clock:1.0 clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of clock_i : signal is "ASSOCIATED_BUSIF l1_i:l1_o:routed_tx_0:routed_tx_1:routed_tx_2:routed_tx_3:routed_tx_4:routed_tx_5:routed_tx_6:routed_tx_7:routed_rx_0:routed_rx_1:routed_rx_2:routed_rx_3:routed_rx_4:routed_rx_5:routed_rx_6:routed_rx_7, ASSOCIATED_RESET reset_n_i";

  attribute X_INTERFACE_INFO of l1_i_tdata : signal is "xilinx.com:interface:axis:1.0 l1_i TDATA";
  attribute X_INTERFACE_INFO of l1_i_tvalid : signal is "xilinx.com:interface:axis:1.0 l1_i TVALID";
  attribute X_INTERFACE_INFO of l1_i_tlast : signal is "xilinx.com:interface:axis:1.0 l1_i TLAST";
  attribute X_INTERFACE_INFO of l1_i_tready : signal is "xilinx.com:interface:axis:1.0 l1_i TREADY";
  attribute X_INTERFACE_INFO of l1_o_tdata : signal is "xilinx.com:interface:axis:1.0 l1_o TDATA";
  attribute X_INTERFACE_INFO of l1_o_tvalid : signal is "xilinx.com:interface:axis:1.0 l1_o TVALID";
  attribute X_INTERFACE_INFO of l1_o_tlast : signal is "xilinx.com:interface:axis:1.0 l1_o TLAST";
  attribute X_INTERFACE_INFO of l1_o_tready : signal is "xilinx.com:interface:axis:1.0 l1_o TREADY";
  attribute X_INTERFACE_INFO of routed_tx_0_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_0 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_0_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_0 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_0_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_0 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_0_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_0 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_1_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_1 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_1_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_1 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_1_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_1 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_1_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_1 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_2_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_2 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_2_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_2 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_2_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_2 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_2_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_2 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_3_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_3 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_3_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_3 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_3_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_3 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_3_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_3 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_4_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_4 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_4_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_4 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_4_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_4 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_4_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_4 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_5_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_5 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_5_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_5 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_5_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_5 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_5_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_5 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_6_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_6 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_6_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_6 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_6_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_6 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_6_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_6 TREADY";
  attribute X_INTERFACE_INFO of routed_tx_7_tdata : signal is "xilinx.com:interface:axis:1.0 routed_tx_7 TDATA";
  attribute X_INTERFACE_INFO of routed_tx_7_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_tx_7 TVALID";
  attribute X_INTERFACE_INFO of routed_tx_7_tlast : signal is "xilinx.com:interface:axis:1.0 routed_tx_7 TLAST";
  attribute X_INTERFACE_INFO of routed_tx_7_tready : signal is "xilinx.com:interface:axis:1.0 routed_tx_7 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_0_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_0 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_0_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_0 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_0_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_0 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_0_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_0 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_1_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_1 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_1_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_1 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_1_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_1 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_1_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_1 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_2_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_2 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_2_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_2 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_2_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_2 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_2_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_2 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_3_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_3 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_3_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_3 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_3_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_3 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_3_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_3 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_4_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_4 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_4_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_4 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_4_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_4 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_4_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_4 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_5_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_5 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_5_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_5 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_5_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_5 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_5_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_5 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_6_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_6 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_6_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_6 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_6_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_6 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_6_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_6 TREADY";
  attribute X_INTERFACE_INFO of routed_rx_7_tdata : signal is "xilinx.com:interface:axis:1.0 routed_rx_7 TDATA";
  attribute X_INTERFACE_INFO of routed_rx_7_tvalid : signal is "xilinx.com:interface:axis:1.0 routed_rx_7 TVALID";
  attribute X_INTERFACE_INFO of routed_rx_7_tlast : signal is "xilinx.com:interface:axis:1.0 routed_rx_7 TLAST";
  attribute X_INTERFACE_INFO of routed_rx_7_tready : signal is "xilinx.com:interface:axis:1.0 routed_rx_7 TREADY";

  constant cfg_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => 1, last => true);

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

  signal l1_rx_s, l1_tx_s : committed_bus_t;
  signal tx_m_s : master_vector(0 to vlan_count_c-1);
  signal tx_s_s : slave_vector(0 to vlan_count_c-1);
  signal rx_m_s : master_vector(0 to vlan_count_c-1);
  signal rx_s_s : slave_vector(0 to vlan_count_c-1);

begin

  -- Flat -> record on the layer-1 side, and back.
  l1_rx_s.req <= framed_flit(data  => std_ulogic_vector(l1_i_tdata),
                             last  => l1_i_tlast = '1',
                             valid => l1_i_tvalid = '1');
  l1_i_tready <= l1_rx_s.ack.ready;

  l1_o_tdata  <= std_logic_vector(l1_tx_s.req.data);
  l1_o_tvalid <= l1_tx_s.req.valid;
  l1_o_tlast  <= l1_tx_s.req.last;
  l1_tx_s.ack <= framed_accept(l1_o_tready = '1');

  vlan_0: if vlan_count_c > 0
  generate
    routed_tx_0_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(0))(0));
    routed_tx_0_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(0)));
    routed_tx_0_tlast  <= to_logic(is_last(cfg_c, tx_m_s(0)));
    tx_s_s(0) <= accept(cfg_c, routed_tx_0_tready = '1');

    rx_m_s(0) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_0_tdata)),
                          valid => routed_rx_0_tvalid = '1',
                          last  => routed_rx_0_tlast = '1');
    routed_rx_0_tready <= to_logic(is_ready(cfg_c, rx_s_s(0)));
  end generate;

  vlan_0_off: if vlan_count_c <= 0
  generate
    routed_tx_0_tdata  <= (others => '0');
    routed_tx_0_tvalid <= '0';
    routed_tx_0_tlast  <= '0';
    routed_rx_0_tready <= '0';
  end generate;

  vlan_1: if vlan_count_c > 1
  generate
    routed_tx_1_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(1))(0));
    routed_tx_1_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(1)));
    routed_tx_1_tlast  <= to_logic(is_last(cfg_c, tx_m_s(1)));
    tx_s_s(1) <= accept(cfg_c, routed_tx_1_tready = '1');

    rx_m_s(1) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_1_tdata)),
                          valid => routed_rx_1_tvalid = '1',
                          last  => routed_rx_1_tlast = '1');
    routed_rx_1_tready <= to_logic(is_ready(cfg_c, rx_s_s(1)));
  end generate;

  vlan_1_off: if vlan_count_c <= 1
  generate
    routed_tx_1_tdata  <= (others => '0');
    routed_tx_1_tvalid <= '0';
    routed_tx_1_tlast  <= '0';
    routed_rx_1_tready <= '0';
  end generate;

  vlan_2: if vlan_count_c > 2
  generate
    routed_tx_2_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(2))(0));
    routed_tx_2_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(2)));
    routed_tx_2_tlast  <= to_logic(is_last(cfg_c, tx_m_s(2)));
    tx_s_s(2) <= accept(cfg_c, routed_tx_2_tready = '1');

    rx_m_s(2) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_2_tdata)),
                          valid => routed_rx_2_tvalid = '1',
                          last  => routed_rx_2_tlast = '1');
    routed_rx_2_tready <= to_logic(is_ready(cfg_c, rx_s_s(2)));
  end generate;

  vlan_2_off: if vlan_count_c <= 2
  generate
    routed_tx_2_tdata  <= (others => '0');
    routed_tx_2_tvalid <= '0';
    routed_tx_2_tlast  <= '0';
    routed_rx_2_tready <= '0';
  end generate;

  vlan_3: if vlan_count_c > 3
  generate
    routed_tx_3_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(3))(0));
    routed_tx_3_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(3)));
    routed_tx_3_tlast  <= to_logic(is_last(cfg_c, tx_m_s(3)));
    tx_s_s(3) <= accept(cfg_c, routed_tx_3_tready = '1');

    rx_m_s(3) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_3_tdata)),
                          valid => routed_rx_3_tvalid = '1',
                          last  => routed_rx_3_tlast = '1');
    routed_rx_3_tready <= to_logic(is_ready(cfg_c, rx_s_s(3)));
  end generate;

  vlan_3_off: if vlan_count_c <= 3
  generate
    routed_tx_3_tdata  <= (others => '0');
    routed_tx_3_tvalid <= '0';
    routed_tx_3_tlast  <= '0';
    routed_rx_3_tready <= '0';
  end generate;

  vlan_4: if vlan_count_c > 4
  generate
    routed_tx_4_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(4))(0));
    routed_tx_4_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(4)));
    routed_tx_4_tlast  <= to_logic(is_last(cfg_c, tx_m_s(4)));
    tx_s_s(4) <= accept(cfg_c, routed_tx_4_tready = '1');

    rx_m_s(4) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_4_tdata)),
                          valid => routed_rx_4_tvalid = '1',
                          last  => routed_rx_4_tlast = '1');
    routed_rx_4_tready <= to_logic(is_ready(cfg_c, rx_s_s(4)));
  end generate;

  vlan_4_off: if vlan_count_c <= 4
  generate
    routed_tx_4_tdata  <= (others => '0');
    routed_tx_4_tvalid <= '0';
    routed_tx_4_tlast  <= '0';
    routed_rx_4_tready <= '0';
  end generate;

  vlan_5: if vlan_count_c > 5
  generate
    routed_tx_5_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(5))(0));
    routed_tx_5_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(5)));
    routed_tx_5_tlast  <= to_logic(is_last(cfg_c, tx_m_s(5)));
    tx_s_s(5) <= accept(cfg_c, routed_tx_5_tready = '1');

    rx_m_s(5) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_5_tdata)),
                          valid => routed_rx_5_tvalid = '1',
                          last  => routed_rx_5_tlast = '1');
    routed_rx_5_tready <= to_logic(is_ready(cfg_c, rx_s_s(5)));
  end generate;

  vlan_5_off: if vlan_count_c <= 5
  generate
    routed_tx_5_tdata  <= (others => '0');
    routed_tx_5_tvalid <= '0';
    routed_tx_5_tlast  <= '0';
    routed_rx_5_tready <= '0';
  end generate;

  vlan_6: if vlan_count_c > 6
  generate
    routed_tx_6_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(6))(0));
    routed_tx_6_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(6)));
    routed_tx_6_tlast  <= to_logic(is_last(cfg_c, tx_m_s(6)));
    tx_s_s(6) <= accept(cfg_c, routed_tx_6_tready = '1');

    rx_m_s(6) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_6_tdata)),
                          valid => routed_rx_6_tvalid = '1',
                          last  => routed_rx_6_tlast = '1');
    routed_rx_6_tready <= to_logic(is_ready(cfg_c, rx_s_s(6)));
  end generate;

  vlan_6_off: if vlan_count_c <= 6
  generate
    routed_tx_6_tdata  <= (others => '0');
    routed_tx_6_tvalid <= '0';
    routed_tx_6_tlast  <= '0';
    routed_rx_6_tready <= '0';
  end generate;

  vlan_7: if vlan_count_c > 7
  generate
    routed_tx_7_tdata  <= std_logic_vector(bytes(cfg_c, tx_m_s(7))(0));
    routed_tx_7_tvalid <= to_logic(is_valid(cfg_c, tx_m_s(7)));
    routed_tx_7_tlast  <= to_logic(is_last(cfg_c, tx_m_s(7)));
    tx_s_s(7) <= accept(cfg_c, routed_tx_7_tready = '1');

    rx_m_s(7) <= transfer(cfg_c,
                          bytes => byte_string'(0 => std_ulogic_vector(routed_rx_7_tdata)),
                          valid => routed_rx_7_tvalid = '1',
                          last  => routed_rx_7_tlast = '1');
    routed_rx_7_tready <= to_logic(is_ready(cfg_c, rx_s_s(7)));
  end generate;

  vlan_7_off: if vlan_count_c <= 7
  generate
    routed_tx_7_tdata  <= (others => '0');
    routed_tx_7_tvalid <= '0';
    routed_tx_7_tlast  <= '0';
    routed_rx_7_tready <= '0';
  end generate;

  dut: nsl_inet.vlan.vlan_path_router
    generic map(
      vlan_id_c        => vids_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      l1_rx_i => l1_rx_s.req,
      l1_rx_o => l1_rx_s.ack,
      l1_tx_o => l1_tx_s.req,
      l1_tx_i => l1_tx_s.ack,

      routed_tx_o => tx_m_s,
      routed_tx_i => tx_s_s,
      routed_rx_i => rx_m_s,
      routed_rx_o => rx_s_s
      );

end architecture;
