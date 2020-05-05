library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

entity routed_router is
  generic(
      slave_port_count : natural range 1 to 8 := 1;
      master_port_count : natural range 1 to 8 := 2;
      cmd_dest_0 : natural range 0 to 7 := 0;
      cmd_dest_1 : natural range 0 to 7 := 0;
      cmd_dest_2 : natural range 0 to 7 := 0;
      cmd_dest_3 : natural range 0 to 7 := 0;
      cmd_dest_4 : natural range 0 to 7 := 0;
      cmd_dest_5 : natural range 0 to 7 := 0;
      cmd_dest_6 : natural range 0 to 7 := 0;
      cmd_dest_7 : natural range 0 to 7 := 0;
      cmd_dest_8 : natural range 0 to 7 := 0;
      cmd_dest_9 : natural range 0 to 7 := 0;
      cmd_dest_10 : natural range 0 to 7 := 0;
      cmd_dest_11 : natural range 0 to 7 := 0;
      cmd_dest_12 : natural range 0 to 7 := 0;
      cmd_dest_13 : natural range 0 to 7 := 0;
      cmd_dest_14 : natural range 0 to 7 := 0;
      cmd_dest_15 : natural range 0 to 7 := 0;
      rsp_dest_0 : natural range 0 to 7 := 0;
      rsp_dest_1 : natural range 0 to 7 := 0;
      rsp_dest_2 : natural range 0 to 7 := 0;
      rsp_dest_3 : natural range 0 to 7 := 0;
      rsp_dest_4 : natural range 0 to 7 := 0;
      rsp_dest_5 : natural range 0 to 7 := 0;
      rsp_dest_6 : natural range 0 to 7 := 0;
      rsp_dest_7 : natural range 0 to 7 := 0;
      rsp_dest_8 : natural range 0 to 7 := 0;
      rsp_dest_9 : natural range 0 to 7 := 0;
      rsp_dest_10 : natural range 0 to 7 := 0;
      rsp_dest_11 : natural range 0 to 7 := 0;
      rsp_dest_12 : natural range 0 to 7 := 0;
      rsp_dest_13 : natural range 0 to 7 := 0;
      rsp_dest_14 : natural range 0 to 7 := 0;
      rsp_dest_15 : natural range 0 to 7 := 0
    );
  port(
    clock : in std_logic;
    resetn : in std_logic;

    s_0_cmd_data : in std_logic_vector(7 downto 0);
    s_0_cmd_last : in std_logic;
    s_0_cmd_valid : in std_logic;
    s_0_cmd_ready : out std_logic;
    s_0_rsp_data : out std_logic_vector(7 downto 0);
    s_0_rsp_last : out std_logic;
    s_0_rsp_valid : out std_logic;
    s_0_rsp_ready : in std_logic;

    s_1_cmd_data : in std_logic_vector(7 downto 0);
    s_1_cmd_last : in std_logic;
    s_1_cmd_valid : in std_logic;
    s_1_cmd_ready : out std_logic;
    s_1_rsp_data : out std_logic_vector(7 downto 0);
    s_1_rsp_last : out std_logic;
    s_1_rsp_valid : out std_logic;
    s_1_rsp_ready : in std_logic;

    s_2_cmd_data : in std_logic_vector(7 downto 0);
    s_2_cmd_last : in std_logic;
    s_2_cmd_valid : in std_logic;
    s_2_cmd_ready : out std_logic;
    s_2_rsp_data : out std_logic_vector(7 downto 0);
    s_2_rsp_last : out std_logic;
    s_2_rsp_valid : out std_logic;
    s_2_rsp_ready : in std_logic;

    s_3_cmd_data : in std_logic_vector(7 downto 0);
    s_3_cmd_last : in std_logic;
    s_3_cmd_valid : in std_logic;
    s_3_cmd_ready : out std_logic;
    s_3_rsp_data : out std_logic_vector(7 downto 0);
    s_3_rsp_last : out std_logic;
    s_3_rsp_valid : out std_logic;
    s_3_rsp_ready : in std_logic;

    s_4_cmd_data : in std_logic_vector(7 downto 0);
    s_4_cmd_last : in std_logic;
    s_4_cmd_valid : in std_logic;
    s_4_cmd_ready : out std_logic;
    s_4_rsp_data : out std_logic_vector(7 downto 0);
    s_4_rsp_last : out std_logic;
    s_4_rsp_valid : out std_logic;
    s_4_rsp_ready : in std_logic;

    s_5_cmd_data : in std_logic_vector(7 downto 0);
    s_5_cmd_last : in std_logic;
    s_5_cmd_valid : in std_logic;
    s_5_cmd_ready : out std_logic;
    s_5_rsp_data : out std_logic_vector(7 downto 0);
    s_5_rsp_last : out std_logic;
    s_5_rsp_valid : out std_logic;
    s_5_rsp_ready : in std_logic;

    s_6_cmd_data : in std_logic_vector(7 downto 0);
    s_6_cmd_last : in std_logic;
    s_6_cmd_valid : in std_logic;
    s_6_cmd_ready : out std_logic;
    s_6_rsp_data : out std_logic_vector(7 downto 0);
    s_6_rsp_last : out std_logic;
    s_6_rsp_valid : out std_logic;
    s_6_rsp_ready : in std_logic;

    s_7_cmd_data : in std_logic_vector(7 downto 0);
    s_7_cmd_last : in std_logic;
    s_7_cmd_valid : in std_logic;
    s_7_cmd_ready : out std_logic;
    s_7_rsp_data : out std_logic_vector(7 downto 0);
    s_7_rsp_last : out std_logic;
    s_7_rsp_valid : out std_logic;
    s_7_rsp_ready : in std_logic;

    m_0_cmd_data : out std_logic_vector(7 downto 0);
    m_0_cmd_last : out std_logic;
    m_0_cmd_valid : out std_logic;
    m_0_cmd_ready : in std_logic;
    m_0_rsp_data : in std_logic_vector(7 downto 0);
    m_0_rsp_last : in std_logic;
    m_0_rsp_valid : in std_logic;
    m_0_rsp_ready : out std_logic;

    m_1_cmd_data : out std_logic_vector(7 downto 0);
    m_1_cmd_last : out std_logic;
    m_1_cmd_valid : out std_logic;
    m_1_cmd_ready : in std_logic;
    m_1_rsp_data : in std_logic_vector(7 downto 0);
    m_1_rsp_last : in std_logic;
    m_1_rsp_valid : in std_logic;
    m_1_rsp_ready : out std_logic;

    m_2_cmd_data : out std_logic_vector(7 downto 0);
    m_2_cmd_last : out std_logic;
    m_2_cmd_valid : out std_logic;
    m_2_cmd_ready : in std_logic;
    m_2_rsp_data : in std_logic_vector(7 downto 0);
    m_2_rsp_last : in std_logic;
    m_2_rsp_valid : in std_logic;
    m_2_rsp_ready : out std_logic;

    m_3_cmd_data : out std_logic_vector(7 downto 0);
    m_3_cmd_last : out std_logic;
    m_3_cmd_valid : out std_logic;
    m_3_cmd_ready : in std_logic;
    m_3_rsp_data : in std_logic_vector(7 downto 0);
    m_3_rsp_last : in std_logic;
    m_3_rsp_valid : in std_logic;
    m_3_rsp_ready : out std_logic;

    m_4_cmd_data : out std_logic_vector(7 downto 0);
    m_4_cmd_last : out std_logic;
    m_4_cmd_valid : out std_logic;
    m_4_cmd_ready : in std_logic;
    m_4_rsp_data : in std_logic_vector(7 downto 0);
    m_4_rsp_last : in std_logic;
    m_4_rsp_valid : in std_logic;
    m_4_rsp_ready : out std_logic;

    m_5_cmd_data : out std_logic_vector(7 downto 0);
    m_5_cmd_last : out std_logic;
    m_5_cmd_valid : out std_logic;
    m_5_cmd_ready : in std_logic;
    m_5_rsp_data : in std_logic_vector(7 downto 0);
    m_5_rsp_last : in std_logic;
    m_5_rsp_valid : in std_logic;
    m_5_rsp_ready : out std_logic;

    m_6_cmd_data : out std_logic_vector(7 downto 0);
    m_6_cmd_last : out std_logic;
    m_6_cmd_valid : out std_logic;
    m_6_cmd_ready : in std_logic;
    m_6_rsp_data : in std_logic_vector(7 downto 0);
    m_6_rsp_last : in std_logic;
    m_6_rsp_valid : in std_logic;
    m_6_rsp_ready : out std_logic;

    m_7_cmd_data : out std_logic_vector(7 downto 0);
    m_7_cmd_last : out std_logic;
    m_7_cmd_valid : out std_logic;
    m_7_cmd_ready : in std_logic;
    m_7_rsp_data : in std_logic_vector(7 downto 0);
    m_7_rsp_last : in std_logic;
    m_7_rsp_valid : in std_logic;
    m_7_rsp_ready : out std_logic
    );
end entity;

architecture rtl of routed_router is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock : signal is "xilinx.com:signal:clock:1.0 clock CLK";
  attribute X_INTERFACE_INFO of resetn : signal is "xilinx.com:signal:reset:1.0 resetn RST";

  attribute X_INTERFACE_PARAMETER of clock : signal is "ASSOCIATED_BUSIF s_0:s_1:s_2:s_3:s_4:s_5:s_6:s_7:m_0:m_1:m_2:m_3:m_4:m_5:m_6:m_7, ASSOCIATED_RESET resetn";
  attribute X_INTERFACE_PARAMETER of resetn : signal is "POLARITY ACTIVE_LOW";
  
  attribute X_INTERFACE_INFO of s_0_cmd_ready : signal is "nsl:interface:routed:1.0 s_0 req_ready";
  attribute X_INTERFACE_INFO of s_0_cmd_valid : signal is "nsl:interface:routed:1.0 s_0 req_valid";
  attribute X_INTERFACE_INFO of s_0_cmd_last  : signal is "nsl:interface:routed:1.0 s_0 req_last";
  attribute X_INTERFACE_INFO of s_0_cmd_data  : signal is "nsl:interface:routed:1.0 s_0 req_data";
  attribute X_INTERFACE_INFO of s_0_rsp_ready : signal is "nsl:interface:routed:1.0 s_0 rsp_ready";
  attribute X_INTERFACE_INFO of s_0_rsp_valid : signal is "nsl:interface:routed:1.0 s_0 rsp_valid";
  attribute X_INTERFACE_INFO of s_0_rsp_last  : signal is "nsl:interface:routed:1.0 s_0 rsp_last";
  attribute X_INTERFACE_INFO of s_0_rsp_data  : signal is "nsl:interface:routed:1.0 s_0 rsp_data";

  attribute X_INTERFACE_INFO of s_1_cmd_ready : signal is "nsl:interface:routed:1.0 s_1 req_ready";
  attribute X_INTERFACE_INFO of s_1_cmd_valid : signal is "nsl:interface:routed:1.0 s_1 req_valid";
  attribute X_INTERFACE_INFO of s_1_cmd_last  : signal is "nsl:interface:routed:1.0 s_1 req_last";
  attribute X_INTERFACE_INFO of s_1_cmd_data  : signal is "nsl:interface:routed:1.0 s_1 req_data";
  attribute X_INTERFACE_INFO of s_1_rsp_ready : signal is "nsl:interface:routed:1.0 s_1 rsp_ready";
  attribute X_INTERFACE_INFO of s_1_rsp_valid : signal is "nsl:interface:routed:1.0 s_1 rsp_valid";
  attribute X_INTERFACE_INFO of s_1_rsp_last  : signal is "nsl:interface:routed:1.0 s_1 rsp_last";
  attribute X_INTERFACE_INFO of s_1_rsp_data  : signal is "nsl:interface:routed:1.0 s_1 rsp_data";

  attribute X_INTERFACE_INFO of s_2_cmd_ready : signal is "nsl:interface:routed:1.0 s_2 req_ready";
  attribute X_INTERFACE_INFO of s_2_cmd_valid : signal is "nsl:interface:routed:1.0 s_2 req_valid";
  attribute X_INTERFACE_INFO of s_2_cmd_last  : signal is "nsl:interface:routed:1.0 s_2 req_last";
  attribute X_INTERFACE_INFO of s_2_cmd_data  : signal is "nsl:interface:routed:1.0 s_2 req_data";
  attribute X_INTERFACE_INFO of s_2_rsp_ready : signal is "nsl:interface:routed:1.0 s_2 rsp_ready";
  attribute X_INTERFACE_INFO of s_2_rsp_valid : signal is "nsl:interface:routed:1.0 s_2 rsp_valid";
  attribute X_INTERFACE_INFO of s_2_rsp_last  : signal is "nsl:interface:routed:1.0 s_2 rsp_last";
  attribute X_INTERFACE_INFO of s_2_rsp_data  : signal is "nsl:interface:routed:1.0 s_2 rsp_data";

  attribute X_INTERFACE_INFO of s_3_cmd_ready : signal is "nsl:interface:routed:1.0 s_3 req_ready";
  attribute X_INTERFACE_INFO of s_3_cmd_valid : signal is "nsl:interface:routed:1.0 s_3 req_valid";
  attribute X_INTERFACE_INFO of s_3_cmd_last  : signal is "nsl:interface:routed:1.0 s_3 req_last";
  attribute X_INTERFACE_INFO of s_3_cmd_data  : signal is "nsl:interface:routed:1.0 s_3 req_data";
  attribute X_INTERFACE_INFO of s_3_rsp_ready : signal is "nsl:interface:routed:1.0 s_3 rsp_ready";
  attribute X_INTERFACE_INFO of s_3_rsp_valid : signal is "nsl:interface:routed:1.0 s_3 rsp_valid";
  attribute X_INTERFACE_INFO of s_3_rsp_last  : signal is "nsl:interface:routed:1.0 s_3 rsp_last";
  attribute X_INTERFACE_INFO of s_3_rsp_data  : signal is "nsl:interface:routed:1.0 s_3 rsp_data";
  
  attribute X_INTERFACE_INFO of s_4_cmd_ready : signal is "nsl:interface:routed:1.0 s_4 req_ready";
  attribute X_INTERFACE_INFO of s_4_cmd_valid : signal is "nsl:interface:routed:1.0 s_4 req_valid";
  attribute X_INTERFACE_INFO of s_4_cmd_last  : signal is "nsl:interface:routed:1.0 s_4 req_last";
  attribute X_INTERFACE_INFO of s_4_cmd_data  : signal is "nsl:interface:routed:1.0 s_4 req_data";
  attribute X_INTERFACE_INFO of s_4_rsp_ready : signal is "nsl:interface:routed:1.0 s_4 rsp_ready";
  attribute X_INTERFACE_INFO of s_4_rsp_valid : signal is "nsl:interface:routed:1.0 s_4 rsp_valid";
  attribute X_INTERFACE_INFO of s_4_rsp_last  : signal is "nsl:interface:routed:1.0 s_4 rsp_last";
  attribute X_INTERFACE_INFO of s_4_rsp_data  : signal is "nsl:interface:routed:1.0 s_4 rsp_data";

  attribute X_INTERFACE_INFO of s_5_cmd_ready : signal is "nsl:interface:routed:1.0 s_5 req_ready";
  attribute X_INTERFACE_INFO of s_5_cmd_valid : signal is "nsl:interface:routed:1.0 s_5 req_valid";
  attribute X_INTERFACE_INFO of s_5_cmd_last  : signal is "nsl:interface:routed:1.0 s_5 req_last";
  attribute X_INTERFACE_INFO of s_5_cmd_data  : signal is "nsl:interface:routed:1.0 s_5 req_data";
  attribute X_INTERFACE_INFO of s_5_rsp_ready : signal is "nsl:interface:routed:1.0 s_5 rsp_ready";
  attribute X_INTERFACE_INFO of s_5_rsp_valid : signal is "nsl:interface:routed:1.0 s_5 rsp_valid";
  attribute X_INTERFACE_INFO of s_5_rsp_last  : signal is "nsl:interface:routed:1.0 s_5 rsp_last";
  attribute X_INTERFACE_INFO of s_5_rsp_data  : signal is "nsl:interface:routed:1.0 s_5 rsp_data";

  attribute X_INTERFACE_INFO of s_6_cmd_ready : signal is "nsl:interface:routed:1.0 s_6 req_ready";
  attribute X_INTERFACE_INFO of s_6_cmd_valid : signal is "nsl:interface:routed:1.0 s_6 req_valid";
  attribute X_INTERFACE_INFO of s_6_cmd_last  : signal is "nsl:interface:routed:1.0 s_6 req_last";
  attribute X_INTERFACE_INFO of s_6_cmd_data  : signal is "nsl:interface:routed:1.0 s_6 req_data";
  attribute X_INTERFACE_INFO of s_6_rsp_ready : signal is "nsl:interface:routed:1.0 s_6 rsp_ready";
  attribute X_INTERFACE_INFO of s_6_rsp_valid : signal is "nsl:interface:routed:1.0 s_6 rsp_valid";
  attribute X_INTERFACE_INFO of s_6_rsp_last  : signal is "nsl:interface:routed:1.0 s_6 rsp_last";
  attribute X_INTERFACE_INFO of s_6_rsp_data  : signal is "nsl:interface:routed:1.0 s_6 rsp_data";

  attribute X_INTERFACE_INFO of s_7_cmd_ready : signal is "nsl:interface:routed:1.0 s_7 req_ready";
  attribute X_INTERFACE_INFO of s_7_cmd_valid : signal is "nsl:interface:routed:1.0 s_7 req_valid";
  attribute X_INTERFACE_INFO of s_7_cmd_last  : signal is "nsl:interface:routed:1.0 s_7 req_last";
  attribute X_INTERFACE_INFO of s_7_cmd_data  : signal is "nsl:interface:routed:1.0 s_7 req_data";
  attribute X_INTERFACE_INFO of s_7_rsp_ready : signal is "nsl:interface:routed:1.0 s_7 rsp_ready";
  attribute X_INTERFACE_INFO of s_7_rsp_valid : signal is "nsl:interface:routed:1.0 s_7 rsp_valid";
  attribute X_INTERFACE_INFO of s_7_rsp_last  : signal is "nsl:interface:routed:1.0 s_7 rsp_last";
  attribute X_INTERFACE_INFO of s_7_rsp_data  : signal is "nsl:interface:routed:1.0 s_7 rsp_data";
  
  attribute X_INTERFACE_INFO of m_0_cmd_ready : signal is "nsl:interface:routed:1.0 m_0 req_ready";
  attribute X_INTERFACE_INFO of m_0_cmd_valid : signal is "nsl:interface:routed:1.0 m_0 req_valid";
  attribute X_INTERFACE_INFO of m_0_cmd_last  : signal is "nsl:interface:routed:1.0 m_0 req_last";
  attribute X_INTERFACE_INFO of m_0_cmd_data  : signal is "nsl:interface:routed:1.0 m_0 req_data";
  attribute X_INTERFACE_INFO of m_0_rsp_ready : signal is "nsl:interface:routed:1.0 m_0 rsp_ready";
  attribute X_INTERFACE_INFO of m_0_rsp_valid : signal is "nsl:interface:routed:1.0 m_0 rsp_valid";
  attribute X_INTERFACE_INFO of m_0_rsp_last  : signal is "nsl:interface:routed:1.0 m_0 rsp_last";
  attribute X_INTERFACE_INFO of m_0_rsp_data  : signal is "nsl:interface:routed:1.0 m_0 rsp_data";

  attribute X_INTERFACE_INFO of m_1_cmd_ready : signal is "nsl:interface:routed:1.0 m_1 req_ready";
  attribute X_INTERFACE_INFO of m_1_cmd_valid : signal is "nsl:interface:routed:1.0 m_1 req_valid";
  attribute X_INTERFACE_INFO of m_1_cmd_last  : signal is "nsl:interface:routed:1.0 m_1 req_last";
  attribute X_INTERFACE_INFO of m_1_cmd_data  : signal is "nsl:interface:routed:1.0 m_1 req_data";
  attribute X_INTERFACE_INFO of m_1_rsp_ready : signal is "nsl:interface:routed:1.0 m_1 rsp_ready";
  attribute X_INTERFACE_INFO of m_1_rsp_valid : signal is "nsl:interface:routed:1.0 m_1 rsp_valid";
  attribute X_INTERFACE_INFO of m_1_rsp_last  : signal is "nsl:interface:routed:1.0 m_1 rsp_last";
  attribute X_INTERFACE_INFO of m_1_rsp_data  : signal is "nsl:interface:routed:1.0 m_1 rsp_data";

  attribute X_INTERFACE_INFO of m_2_cmd_ready : signal is "nsl:interface:routed:1.0 m_2 req_ready";
  attribute X_INTERFACE_INFO of m_2_cmd_valid : signal is "nsl:interface:routed:1.0 m_2 req_valid";
  attribute X_INTERFACE_INFO of m_2_cmd_last  : signal is "nsl:interface:routed:1.0 m_2 req_last";
  attribute X_INTERFACE_INFO of m_2_cmd_data  : signal is "nsl:interface:routed:1.0 m_2 req_data";
  attribute X_INTERFACE_INFO of m_2_rsp_ready : signal is "nsl:interface:routed:1.0 m_2 rsp_ready";
  attribute X_INTERFACE_INFO of m_2_rsp_valid : signal is "nsl:interface:routed:1.0 m_2 rsp_valid";
  attribute X_INTERFACE_INFO of m_2_rsp_last  : signal is "nsl:interface:routed:1.0 m_2 rsp_last";
  attribute X_INTERFACE_INFO of m_2_rsp_data  : signal is "nsl:interface:routed:1.0 m_2 rsp_data";

  attribute X_INTERFACE_INFO of m_3_cmd_ready : signal is "nsl:interface:routed:1.0 m_3 req_ready";
  attribute X_INTERFACE_INFO of m_3_cmd_valid : signal is "nsl:interface:routed:1.0 m_3 req_valid";
  attribute X_INTERFACE_INFO of m_3_cmd_last  : signal is "nsl:interface:routed:1.0 m_3 req_last";
  attribute X_INTERFACE_INFO of m_3_cmd_data  : signal is "nsl:interface:routed:1.0 m_3 req_data";
  attribute X_INTERFACE_INFO of m_3_rsp_ready : signal is "nsl:interface:routed:1.0 m_3 rsp_ready";
  attribute X_INTERFACE_INFO of m_3_rsp_valid : signal is "nsl:interface:routed:1.0 m_3 rsp_valid";
  attribute X_INTERFACE_INFO of m_3_rsp_last  : signal is "nsl:interface:routed:1.0 m_3 rsp_last";
  attribute X_INTERFACE_INFO of m_3_rsp_data  : signal is "nsl:interface:routed:1.0 m_3 rsp_data";
  
  attribute X_INTERFACE_INFO of m_4_cmd_ready : signal is "nsl:interface:routed:1.0 m_4 req_ready";
  attribute X_INTERFACE_INFO of m_4_cmd_valid : signal is "nsl:interface:routed:1.0 m_4 req_valid";
  attribute X_INTERFACE_INFO of m_4_cmd_last  : signal is "nsl:interface:routed:1.0 m_4 req_last";
  attribute X_INTERFACE_INFO of m_4_cmd_data  : signal is "nsl:interface:routed:1.0 m_4 req_data";
  attribute X_INTERFACE_INFO of m_4_rsp_ready : signal is "nsl:interface:routed:1.0 m_4 rsp_ready";
  attribute X_INTERFACE_INFO of m_4_rsp_valid : signal is "nsl:interface:routed:1.0 m_4 rsp_valid";
  attribute X_INTERFACE_INFO of m_4_rsp_last  : signal is "nsl:interface:routed:1.0 m_4 rsp_last";
  attribute X_INTERFACE_INFO of m_4_rsp_data  : signal is "nsl:interface:routed:1.0 m_4 rsp_data";

  attribute X_INTERFACE_INFO of m_5_cmd_ready : signal is "nsl:interface:routed:1.0 m_5 req_ready";
  attribute X_INTERFACE_INFO of m_5_cmd_valid : signal is "nsl:interface:routed:1.0 m_5 req_valid";
  attribute X_INTERFACE_INFO of m_5_cmd_last  : signal is "nsl:interface:routed:1.0 m_5 req_last";
  attribute X_INTERFACE_INFO of m_5_cmd_data  : signal is "nsl:interface:routed:1.0 m_5 req_data";
  attribute X_INTERFACE_INFO of m_5_rsp_ready : signal is "nsl:interface:routed:1.0 m_5 rsp_ready";
  attribute X_INTERFACE_INFO of m_5_rsp_valid : signal is "nsl:interface:routed:1.0 m_5 rsp_valid";
  attribute X_INTERFACE_INFO of m_5_rsp_last  : signal is "nsl:interface:routed:1.0 m_5 rsp_last";
  attribute X_INTERFACE_INFO of m_5_rsp_data  : signal is "nsl:interface:routed:1.0 m_5 rsp_data";

  attribute X_INTERFACE_INFO of m_6_cmd_ready : signal is "nsl:interface:routed:1.0 m_6 req_ready";
  attribute X_INTERFACE_INFO of m_6_cmd_valid : signal is "nsl:interface:routed:1.0 m_6 req_valid";
  attribute X_INTERFACE_INFO of m_6_cmd_last  : signal is "nsl:interface:routed:1.0 m_6 req_last";
  attribute X_INTERFACE_INFO of m_6_cmd_data  : signal is "nsl:interface:routed:1.0 m_6 req_data";
  attribute X_INTERFACE_INFO of m_6_rsp_ready : signal is "nsl:interface:routed:1.0 m_6 rsp_ready";
  attribute X_INTERFACE_INFO of m_6_rsp_valid : signal is "nsl:interface:routed:1.0 m_6 rsp_valid";
  attribute X_INTERFACE_INFO of m_6_rsp_last  : signal is "nsl:interface:routed:1.0 m_6 rsp_last";
  attribute X_INTERFACE_INFO of m_6_rsp_data  : signal is "nsl:interface:routed:1.0 m_6 rsp_data";

  attribute X_INTERFACE_INFO of m_7_cmd_ready : signal is "nsl:interface:routed:1.0 m_7 req_ready";
  attribute X_INTERFACE_INFO of m_7_cmd_valid : signal is "nsl:interface:routed:1.0 m_7 req_valid";
  attribute X_INTERFACE_INFO of m_7_cmd_last  : signal is "nsl:interface:routed:1.0 m_7 req_last";
  attribute X_INTERFACE_INFO of m_7_cmd_data  : signal is "nsl:interface:routed:1.0 m_7 req_data";
  attribute X_INTERFACE_INFO of m_7_rsp_ready : signal is "nsl:interface:routed:1.0 m_7 rsp_ready";
  attribute X_INTERFACE_INFO of m_7_rsp_valid : signal is "nsl:interface:routed:1.0 m_7 rsp_valid";
  attribute X_INTERFACE_INFO of m_7_rsp_last  : signal is "nsl:interface:routed:1.0 m_7 rsp_last";
  attribute X_INTERFACE_INFO of m_7_rsp_data  : signal is "nsl:interface:routed:1.0 m_7 rsp_data";

  signal s_cmd_req : nsl_bnoc.routed.routed_req_array(0 to 7);
  signal s_cmd_ack : nsl_bnoc.routed.routed_ack_array(0 to 7);
  signal s_rsp_req : nsl_bnoc.routed.routed_req_array(0 to 7);
  signal s_rsp_ack : nsl_bnoc.routed.routed_ack_array(0 to 7);
  signal m_cmd_req : nsl_bnoc.routed.routed_req_array(0 to 7);
  signal m_cmd_ack : nsl_bnoc.routed.routed_ack_array(0 to 7);
  signal m_rsp_req : nsl_bnoc.routed.routed_req_array(0 to 7);
  signal m_rsp_ack : nsl_bnoc.routed.routed_ack_array(0 to 7);
  
begin

  s_cmd_req(0).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_0_cmd_data));
  s_cmd_req(0).valid <= s_0_cmd_valid;
  s_cmd_req(0).last  <= s_0_cmd_last;
  s_0_cmd_ready      <= s_cmd_ack(0).ready;
  s_0_rsp_data       <= std_logic_vector(s_rsp_req(0).data);
  s_0_rsp_valid      <= s_rsp_req(0).valid;
  s_0_rsp_last       <= s_rsp_req(0).last;
  s_rsp_ack(0).ready <= s_0_rsp_ready;
  s_cmd_req(1).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_1_cmd_data));
  s_cmd_req(1).valid <= s_1_cmd_valid;
  s_cmd_req(1).last  <= s_1_cmd_last;
  s_1_cmd_ready      <= s_cmd_ack(1).ready;
  s_1_rsp_data       <= std_logic_vector(s_rsp_req(1).data);
  s_1_rsp_valid      <= s_rsp_req(1).valid;
  s_1_rsp_last       <= s_rsp_req(1).last;
  s_rsp_ack(1).ready <= s_1_rsp_ready;
  s_cmd_req(2).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_2_cmd_data));
  s_cmd_req(2).valid <= s_2_cmd_valid;
  s_cmd_req(2).last  <= s_2_cmd_last;
  s_2_cmd_ready      <= s_cmd_ack(2).ready;
  s_2_rsp_data       <= std_logic_vector(s_rsp_req(2).data);
  s_2_rsp_valid      <= s_rsp_req(2).valid;
  s_2_rsp_last       <= s_rsp_req(2).last;
  s_rsp_ack(2).ready <= s_2_rsp_ready;
  s_cmd_req(3).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_3_cmd_data));
  s_cmd_req(3).valid <= s_3_cmd_valid;
  s_cmd_req(3).last  <= s_3_cmd_last;
  s_3_cmd_ready      <= s_cmd_ack(3).ready;
  s_3_rsp_data       <= std_logic_vector(s_rsp_req(3).data);
  s_3_rsp_valid      <= s_rsp_req(3).valid;
  s_3_rsp_last       <= s_rsp_req(3).last;
  s_rsp_ack(3).ready <= s_3_rsp_ready;
  s_cmd_req(4).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_4_cmd_data));
  s_cmd_req(4).valid <= s_4_cmd_valid;
  s_cmd_req(4).last  <= s_4_cmd_last;
  s_4_cmd_ready      <= s_cmd_ack(4).ready;
  s_4_rsp_data       <= std_logic_vector(s_rsp_req(4).data);
  s_4_rsp_valid      <= s_rsp_req(4).valid;
  s_4_rsp_last       <= s_rsp_req(4).last;
  s_rsp_ack(4).ready <= s_4_rsp_ready;
  s_cmd_req(5).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_5_cmd_data));
  s_cmd_req(5).valid <= s_5_cmd_valid;
  s_cmd_req(5).last  <= s_5_cmd_last;
  s_5_cmd_ready      <= s_cmd_ack(5).ready;
  s_5_rsp_data       <= std_logic_vector(s_rsp_req(5).data);
  s_5_rsp_valid      <= s_rsp_req(5).valid;
  s_5_rsp_last       <= s_rsp_req(5).last;
  s_rsp_ack(5).ready <= s_5_rsp_ready;
  s_cmd_req(6).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_6_cmd_data));
  s_cmd_req(6).valid <= s_6_cmd_valid;
  s_cmd_req(6).last  <= s_6_cmd_last;
  s_6_cmd_ready      <= s_cmd_ack(6).ready;
  s_6_rsp_data       <= std_logic_vector(s_rsp_req(6).data);
  s_6_rsp_valid      <= s_rsp_req(6).valid;
  s_6_rsp_last       <= s_rsp_req(6).last;
  s_rsp_ack(6).ready <= s_6_rsp_ready;
  s_cmd_req(7).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(s_7_cmd_data));
  s_cmd_req(7).valid <= s_7_cmd_valid;
  s_cmd_req(7).last  <= s_7_cmd_last;
  s_7_cmd_ready      <= s_cmd_ack(7).ready;
  s_7_rsp_data       <= std_logic_vector(s_rsp_req(7).data);
  s_7_rsp_valid      <= s_rsp_req(7).valid;
  s_7_rsp_last       <= s_rsp_req(7).last;
  s_rsp_ack(7).ready <= s_7_rsp_ready;

  m_0_cmd_data       <= std_logic_vector(m_cmd_req(0).data);
  m_0_cmd_valid      <= m_cmd_req(0).valid;
  m_0_cmd_last       <= m_cmd_req(0).last;
  m_cmd_ack(0).ready <= m_0_cmd_ready;
  m_rsp_req(0).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_0_rsp_data));
  m_rsp_req(0).valid <= m_0_rsp_valid;
  m_rsp_req(0).last  <= m_0_rsp_last;
  m_0_rsp_ready      <= m_rsp_ack(0).ready;
  m_1_cmd_data       <= std_logic_vector(m_cmd_req(1).data);
  m_1_cmd_valid      <= m_cmd_req(1).valid;
  m_1_cmd_last       <= m_cmd_req(1).last;
  m_cmd_ack(1).ready <= m_1_cmd_ready;
  m_rsp_req(1).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_1_rsp_data));
  m_rsp_req(1).valid <= m_1_rsp_valid;
  m_rsp_req(1).last  <= m_1_rsp_last;
  m_1_rsp_ready      <= m_rsp_ack(1).ready;
  m_2_cmd_data       <= std_logic_vector(m_cmd_req(2).data);
  m_2_cmd_valid      <= m_cmd_req(2).valid;
  m_2_cmd_last       <= m_cmd_req(2).last;
  m_cmd_ack(2).ready <= m_2_cmd_ready;
  m_rsp_req(2).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_2_rsp_data));
  m_rsp_req(2).valid <= m_2_rsp_valid;
  m_rsp_req(2).last  <= m_2_rsp_last;
  m_2_rsp_ready      <= m_rsp_ack(2).ready;
  m_3_cmd_data       <= std_logic_vector(m_cmd_req(3).data);
  m_3_cmd_valid      <= m_cmd_req(3).valid;
  m_3_cmd_last       <= m_cmd_req(3).last;
  m_cmd_ack(3).ready <= m_3_cmd_ready;
  m_rsp_req(3).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_3_rsp_data));
  m_rsp_req(3).valid <= m_3_rsp_valid;
  m_rsp_req(3).last  <= m_3_rsp_last;
  m_3_rsp_ready      <= m_rsp_ack(3).ready;
  m_4_cmd_data       <= std_logic_vector(m_cmd_req(4).data);
  m_4_cmd_valid      <= m_cmd_req(4).valid;
  m_4_cmd_last       <= m_cmd_req(4).last;
  m_cmd_ack(4).ready <= m_4_cmd_ready;
  m_rsp_req(4).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_4_rsp_data));
  m_rsp_req(4).valid <= m_4_rsp_valid;
  m_rsp_req(4).last  <= m_4_rsp_last;
  m_4_rsp_ready      <= m_rsp_ack(4).ready;
  m_5_cmd_data       <= std_logic_vector(m_cmd_req(5).data);
  m_5_cmd_valid      <= m_cmd_req(5).valid;
  m_5_cmd_last       <= m_cmd_req(5).last;
  m_cmd_ack(5).ready <= m_5_cmd_ready;
  m_rsp_req(5).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_5_rsp_data));
  m_rsp_req(5).valid <= m_5_rsp_valid;
  m_rsp_req(5).last  <= m_5_rsp_last;
  m_5_rsp_ready      <= m_rsp_ack(5).ready;
  m_6_cmd_data       <= std_logic_vector(m_cmd_req(6).data);
  m_6_cmd_valid      <= m_cmd_req(6).valid;
  m_6_cmd_last       <= m_cmd_req(6).last;
  m_cmd_ack(6).ready <= m_6_cmd_ready;
  m_rsp_req(6).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_6_rsp_data));
  m_rsp_req(6).valid <= m_6_rsp_valid;
  m_rsp_req(6).last  <= m_6_rsp_last;
  m_6_rsp_ready      <= m_rsp_ack(6).ready;
  m_7_cmd_data       <= std_logic_vector(m_cmd_req(7).data);
  m_7_cmd_valid      <= m_cmd_req(7).valid;
  m_7_cmd_last       <= m_cmd_req(7).last;
  m_cmd_ack(7).ready <= m_7_cmd_ready;
  m_rsp_req(7).data  <= nsl_bnoc.framed.framed_data_t(std_ulogic_vector(m_7_rsp_data));
  m_rsp_req(7).valid <= m_7_rsp_valid;
  m_rsp_req(7).last  <= m_7_rsp_last;
  m_7_rsp_ready      <= m_rsp_ack(7).ready;
  
  command_router: nsl_bnoc.routed.routed_router
    generic map(
      in_port_count => slave_port_count,
      out_port_count => master_port_count,
      routing_table => (cmd_dest_0, cmd_dest_1, cmd_dest_2, cmd_dest_3,
                        cmd_dest_4, cmd_dest_5, cmd_dest_6, cmd_dest_7,
                        cmd_dest_8, cmd_dest_9, cmd_dest_10, cmd_dest_11,
                        cmd_dest_12, cmd_dest_13, cmd_dest_14, cmd_dest_15)
      )
    port map(
      p_resetn => resetn,
      p_clk => clock,

      p_in_val => s_cmd_req(0 to slave_port_count-1),
      p_in_ack => s_cmd_ack(0 to slave_port_count-1),
      p_out_val => m_cmd_req(0 to master_port_count-1),
      p_out_ack => m_cmd_ack(0 to master_port_count-1)
      );
  
  response_router: nsl_bnoc.routed.routed_router
    generic map(
      in_port_count => master_port_count,
      out_port_count => slave_port_count,
      routing_table => (rsp_dest_0, rsp_dest_1, rsp_dest_2, rsp_dest_3,
                        rsp_dest_4, rsp_dest_5, rsp_dest_6, rsp_dest_7,
                        rsp_dest_8, rsp_dest_9, rsp_dest_10, rsp_dest_11,
                        rsp_dest_12, rsp_dest_13, rsp_dest_14, rsp_dest_15)
      )
    port map(
      p_resetn => resetn,
      p_clk => clock,

      p_in_val => m_rsp_req(0 to master_port_count-1),
      p_in_ack => m_rsp_ack(0 to master_port_count-1),
      p_out_val => s_rsp_req(0 to slave_port_count-1),
      p_out_ack => s_rsp_ack(0 to slave_port_count-1)
      );

end;
