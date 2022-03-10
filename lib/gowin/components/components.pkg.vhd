-- Forward declaration for gowin target library
-- There is no distinction of various chip series

LIBRARY ieee;
use ieee.std_logic_1164.all;

package components is
  attribute syn_black_box: boolean ;
  attribute syn_black_box of Components : package is true;
  attribute black_box_pad_pin: string;
  attribute syn_noprune : boolean;
  attribute xc_map: string;
  attribute xc_map of Components : package is "lut";

  COMPONENT CLKDIV2
    GENERIC (
      GSREN : STRING := "false"
      );
    PORT (
      HCLKIN : IN std_logic;
      RESETN : IN std_logic;
      CLKOUT : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of CLKDIV2 : Component is true;

  COMPONENT DCC
    GENERIC (
      DCC_EN : bit := '1';
      FCLKIN : REAL := 50.0
      );
    PORT (
      CLKOUT: OUT STD_LOGIC;
      CLKIN : IN STD_LOGIC
      );
  end COMPONENT;
  attribute syn_black_box of DCC : Component is true;

  COMPONENT DHCENC
    GENERIC (
      DCC_EN : bit := '1';
      FCLKIN : REAL := 50.0
      );
    PORT (
      CLKOUT: OUT STD_LOGIC;
      CLKIN : IN STD_LOGIC
      );
  end COMPONENT;
  attribute syn_black_box of DHCENC : Component is true;

  COMPONENT EMCU
    PORT(
      FCLK : IN std_logic;
      PORESETN : IN std_logic;
      SYSRESETN : IN std_logic;
      RTCSRCCLK : IN std_logic;
      IOEXPOUTPUTO : OUT std_logic_vector(15 downto 0);
      IOEXPOUTPUTENO : OUT std_logic_vector(15 downto 0);
      IOEXPINPUTI : IN std_logic_vector(15 downto 0);
      UART0TXDO : OUT std_logic;
      UART1TXDO : OUT std_logic;
      UART0BAUDTICK : OUT std_logic;
      UART1BAUDTICK : OUT std_logic;
      UART0RXDI : IN std_logic;
      UART1RXDI : IN std_logic;
      INTMONITOR : OUT std_logic;
      MTXHRESETN : OUT std_logic;
      SRAM0ADDR : OUT std_logic_vector(12 downto 0);
      SRAM0WREN : OUT std_logic_vector(3 downto 0);
      SRAM0WDATA : OUT std_logic_vector(31 downto 0);
      SRAM0CS : OUT std_logic;
      SRAM0RDATA : in std_logic_vector(31 downto 0);

      TARGFLASH0HSEL : OUT std_logic;
      TARGFLASH0HADDR : OUT std_logic_vector(28 downto 0);
      TARGFLASH0HTRANS : OUT std_logic_vector(1 downto 0);
      TARGFLASH0HSIZE : OUT std_logic_vector(2 downto 0);
      TARGFLASH0HBURST : OUT std_logic_vector(2 downto 0);
      TARGFLASH0HREADYMUX : OUT std_logic;
      TARGFLASH0HRDATA : IN std_logic_vector(31 downto 0);
      TARGFLASH0HRUSER : IN std_logic_vector(2 downto 0);
      TARGFLASH0HRESP : IN std_logic;
      TARGFLASH0EXRESP : IN std_logic;
      TARGFLASH0HREADYOUT : IN std_logic;

      TARGEXP0HSEL : OUT std_logic;
      TARGEXP0HADDR : OUT std_logic_vector(31 downto 0);
      TARGEXP0HTRANS : OUT std_logic_vector(1 downto 0);
      TARGEXP0HWRITE : OUT std_logic;
      TARGEXP0HSIZE : OUT std_logic_vector(2 downto 0);
      TARGEXP0HBURST : OUT std_logic_vector(2 downto 0);
      TARGEXP0HPROT : OUT std_logic_vector(3 downto 0);
      TARGEXP0MEMATTR : OUT std_logic_vector(1 downto 0);
      TARGEXP0EXREQ : OUT std_logic;
      TARGEXP0HMASTER : OUT std_logic_vector(3 downto 0);
      TARGEXP0HWDATA : OUT std_logic_vector(31 downto 0);
      TARGEXP0HMASTLOCK : OUT std_logic;
      TARGEXP0HREADYMUX : OUT std_logic;
      TARGEXP0HAUSER : OUT std_logic;
      TARGEXP0HWUSER : OUT std_logic_vector(3 downto 0);
      TARGEXP0HRDATA : IN std_logic_vector(31 downto 0);
      TARGEXP0HREADYOUT : IN std_logic;
      TARGEXP0HRESP : IN std_logic;
      TARGEXP0EXRESP : IN std_logic;
      TARGEXP0HRUSER : IN std_logic_vector(2 downto 0);

      INITEXP0HRDATA : OUT std_logic_vector(31 downto 0);
      INITEXP0HREADY : OUT std_logic;
      INITEXP0HRESP : OUT std_logic;
      INITEXP0EXRESP : OUT std_logic;
      INITEXP0HRUSER : OUT std_logic_vector(2 downto 0);
      INITEXP0HSEL : IN std_logic;
      INITEXP0HADDR : IN std_logic_vector(31 downto 0);
      INITEXP0HTRANS : IN std_logic_vector(1 downto 0);
      INITEXP0HWRITE : IN std_logic;
      INITEXP0HSIZE : IN std_logic_vector(2 downto 0);
      INITEXP0HBURST : IN std_logic_vector(2 downto 0);
      INITEXP0HPROT : IN std_logic_vector(3 downto 0);
      INITEXP0MEMATTR : IN std_logic_vector(1 downto 0);
      INITEXP0EXREQ : IN std_logic;
      INITEXP0HMASTER : IN std_logic_vector(3 downto 0);
      INITEXP0HWDATA : IN std_logic_vector(31 downto 0);
      INITEXP0HMASTLOCK : IN std_logic;
      INITEXP0HAUSER : IN std_logic;
      INITEXP0HWUSER : IN std_logic_vector(3 downto 0);

      APBTARGEXP2PSTRB : OUT std_logic_vector(3 downto 0);
      APBTARGEXP2PPROT : OUT std_logic_vector(2 downto 0);
      APBTARGEXP2PSEL : OUT std_logic;
      APBTARGEXP2PENABLE : OUT std_logic;
      APBTARGEXP2PADDR : OUT std_logic_vector(11 downto 0);
      APBTARGEXP2PWRITE : OUT std_logic;
      APBTARGEXP2PWDATA : OUT std_logic_vector(31 downto 0);
      APBTARGEXP2PRDATA : IN std_logic_vector(31 downto 0);
      APBTARGEXP2PREADY : IN std_logic;
      APBTARGEXP2PSLVERR : IN std_logic;

      MTXREMAP : IN std_logic_vector(3 downto 0);

      DAPTDO : OUT std_logic;
      DAPJTAGNSW : OUT std_logic;
      DAPNTDOEN : OUT std_logic;
      DAPSWDITMS : IN std_logic;
      DAPTDI : IN std_logic;
      DAPNTRST : IN std_logic;
      DAPSWCLKTCK : IN std_logic;

      TPIUTRACEDATA : OUT std_logic_vector(3 downto 0);
      TPIUTRACECLK : OUT std_logic;
      GPINT : IN std_logic_vector(4 downto 0);
      FLASHERR : IN std_logic;
      FLASHINT : IN std_logic
      );
  end COMPONENT;
  attribute syn_black_box of EMCU : Component is true;

  COMPONENT FLASH64K
    PORT(
      XADR : IN std_logic_vector(4 downto 0);
      YADR : IN std_logic_vector(5 downto 0);
      XE,YE,SE:IN std_logic;
      DIN : IN std_logic_vector(31 downto 0);
      ERASE,PROG,NVSTR: IN std_logic;
      SLEEP : IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end COMPONENT;
  attribute syn_black_box of FLASH64K : Component is true;

  COMPONENT FLASH64KZ
    PORT(
      XADR : IN std_logic_vector(4 downto 0);
      YADR : IN std_logic_vector(5 downto 0);
      XE,YE,SE:IN std_logic;
      DIN : IN std_logic_vector(31 downto 0);
      ERASE,PROG,NVSTR: IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end COMPONENT;
  attribute syn_black_box of FLASH64KZ : Component is true;

  COMPONENT I3C
    GENERIC (
      ADDRESS : bit_vector := "0000000"
      );
    PORT (
      LGYS, CMS, ACS, AAS, STOPS, STRTS : in std_logic;
      LGYO, CMO, ACO, AAO, SIO, STOPO, STRTO : out std_logic;
      LGYC, CMC, ACC, AAC, SIC, STOPC, STRTC : in std_logic;
      STRTHDS, SENDAHS, SENDALS, ACKHS : in std_logic;
      ACKLS, STOPSUS, STOPHDS, SENDDHS : in std_logic;
      SENDDLS, RECVDHS, RECVDLS, ADDRS : in std_logic;
      PARITYERROR : out std_logic;
      DI : in std_logic_vector(7 downto 0);
      DOBUF : out std_logic_vector(7 downto 0);
      DO : out std_logic_vector(7 downto 0);
      STATE : out std_logic_vector(7 downto 0);
      SDAI, SCLI : in std_logic;
      SDAO, SCLO : out std_logic;
      SDAOEN, SCLOEN : out std_logic;
      SDAPULLO, SCLPULLO : out std_logic;
      SDAPULLOEN, SCLPULLOEN : out std_logic;
      CE, RESET, CLK : in std_logic
      );
  end COMPONENT;
  attribute syn_black_box of I3C : Component is true;

  COMPONENT IODELAYA
    GENERIC (
      C_STATIC_DLY : integer := 0
      );
    PORT (
      DI : IN std_logic;
      SDTAP : IN std_logic;
      SETN : IN std_logic;
      VALUE : IN std_logic;
      DO : OUT std_logic;
      DF : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of IODELAYA : Component is true;

  COMPONENT IODELAYC
    GENERIC (
      C_STATIC_DLY : integer := 0;
      DYN_DA_SEL : STRING := "false";
      DA_SEL : bit_vector := "00"
      );
    PORT (
      DI : IN std_logic;
      SDTAP : IN std_logic;
      SETN : IN std_logic;
      VALUE : IN std_logic;
      DASEL : IN std_logic_vector(1 downto 0);
      DAADJ : IN std_logic_vector(1 downto 0);
      DO : OUT std_logic;
      DAO : OUT std_logic;
      DF : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of IODELAYC : Component is true;


  COMPONENT PLLVR
    GENERIC(
      FCLKIN : STRING := "100.0";
      DEVICE : STRING := "GW1NS-4";
      DYN_IDIV_SEL : STRING := "false";
      IDIV_SEL : integer := 0;
      DYN_FBDIV_SEL : STRING := "false";
      FBDIV_SEL : integer := 0;
      DYN_ODIV_SEL : STRING := "false";
      ODIV_SEL : integer := 8;
      PSDA_SEL : STRING := "0000";
      DYN_DA_EN : STRING := "false";
      DUTYDA_SEL : STRING := "1000";
      CLKOUT_FT_DIR : bit := '1';
      CLKOUTP_FT_DIR : bit := '1';
      CLKOUT_DLY_STEP : integer := 0;
      CLKOUTP_DLY_STEP : integer := 0;

      CLKOUTD3_SRC : STRING := "CLKOUT";
      CLKFB_SEL : STRING := "internal";
      CLKOUT_BYPASS : STRING := "false";
      CLKOUTP_BYPASS : STRING := "false";
      CLKOUTD_BYPASS : STRING := "false";
      CLKOUTD_SRC : STRING := "CLKOUT";
      DYN_SDIV_SEL : integer := 2
      );
    PORT(
      CLKIN : IN std_logic;
      CLKFB : IN std_logic:='0';
      IDSEL : In std_logic_vector(5 downto 0);
      FBDSEL : In std_logic_vector(5 downto 0);
      ODSEL : In std_logic_vector(5 downto 0);
      RESET : in std_logic:='0';
      RESET_P : in std_logic:='0';
      PSDA,FDLY : In std_logic_vector(3 downto 0);
      DUTYDA : In std_logic_vector(3 downto 0);
      VREN : in std_logic;
      LOCK : OUT std_logic;
      CLKOUT : OUT std_logic;
      CLKOUTD : out std_logic;
      CLKOUTP : out std_logic;
      CLKOUTD3 : out std_logic
      );
  end COMPONENT;
  attribute syn_black_box of PLLVR : Component is true;

  COMPONENT rPLL
    GENERIC(
      FCLKIN : STRING := "100.0";
      DEVICE : STRING := "GW1N-4";
      DYN_IDIV_SEL : STRING := "false";
      IDIV_SEL : integer := 0;
      DYN_FBDIV_SEL : STRING := "false";
      FBDIV_SEL : integer := 0;
      DYN_ODIV_SEL : STRING := "false";
      ODIV_SEL : integer := 8;
      PSDA_SEL : STRING := "0000";
      DYN_DA_EN : STRING := "false";
      DUTYDA_SEL : STRING := "1000";
      CLKOUT_FT_DIR : bit := '1';
      CLKOUTP_FT_DIR : bit := '1';
      CLKOUT_DLY_STEP : integer := 0;
      CLKOUTP_DLY_STEP : integer := 0;

      CLKOUTD3_SRC : STRING := "CLKOUT";
      CLKFB_SEL : STRING := "internal";
      CLKOUT_BYPASS : STRING := "false";
      CLKOUTP_BYPASS : STRING := "false";
      CLKOUTD_BYPASS : STRING := "false";
      CLKOUTD_SRC : STRING := "CLKOUT";
      DYN_SDIV_SEL : integer := 2
      );
    PORT(
      CLKIN : IN std_logic;
      CLKFB : IN std_logic:='0';
      IDSEL : In std_logic_vector(5 downto 0);
      FBDSEL : In std_logic_vector(5 downto 0);
      ODSEL : In std_logic_vector(5 downto 0);
      RESET : in std_logic:='0';
      RESET_P : in std_logic:='0';
      PSDA,FDLY : In std_logic_vector(3 downto 0);
      DUTYDA : In std_logic_vector(3 downto 0);
      LOCK : OUT std_logic;
      CLKOUT : OUT std_logic;
      CLKOUTD : out std_logic;
      CLKOUTP : out std_logic;
      CLKOUTD3 : out std_logic
      );
  end COMPONENT;
  attribute syn_black_box of rPLL : Component is true;

  COMPONENT SPMI
    GENERIC(
      FUNCTION_CTRL : bit_vector := B"0000000";
      MSID_CLKSEL : bit_vector := B"0000000";
      RESPOND_DELAY : bit_vector := B"0000";
      SCLK_NORMAL_PERIOD : bit_vector := B"0000000";
      SCLK_LOW_PERIOD : bit_vector := B"0000000";
      CLK_FREQ : bit_vector := B"0000000";
      SHUTDOWN_BY_ENABLE : bit := '0'
      );
    PORT(
      ADDRO : OUT std_logic_vector(3 downto 0);
      DATAO : OUT std_logic_vector(7 downto 0);
      STATE : OUT std_logic_vector(15 downto 0);
      CMD : OUT std_logic_vector(3 downto 0);

      CLKEXT, ENEXT : IN std_logic;
      SDATA : INOUT std_logic;
      SCLK : INOUT std_logic;

      CLK, CE, RESETN, LOCRESET : IN std_logic;
      PA, SA, CA : IN std_logic;
      ADDRI : IN std_logic_vector(3 downto 0);
      DATAI : IN std_logic_vector(7 downto 0)
      );
  end COMPONENT;
  attribute syn_black_box of SPMI : Component is true;
  attribute black_box_pad_pin of SPMI : Component is "CLKEXT, ENEXT, SDATA, SCLK";


  COMPONENT MIPI_OBUF_A is
    PORT (
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic;
      IB : IN std_logic;
      IL : IN std_logic;
      MODESEL : IN std_logic
      );
  end COMPONENT;
  attribute syn_black_box of MIPI_OBUF_A : Component is true;
  attribute black_box_pad_pin of MIPI_OBUF_A : Component is "O, OB";

  COMPONENT IODELAYB is
    GENERIC (
      C_STATIC_DLY : integer := 0;
      DELAY_MUX : bit_vector := "00";
      DA_SEL : bit_vector := "00"

      );
    PORT (
      DI : IN std_logic;
      SDTAP : IN std_logic;
      SETN : IN std_logic;
      VALUE : IN std_logic;
      DAADJ : IN std_logic_vector(1 downto 0);
      DO : OUT std_logic;
      DAO : OUT std_logic;
      DF : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of IODELAYB : Component is true;

  COMPONENT PLLO is
    GENERIC(
      FCLKIN : STRING := "100.0";
      DYN_IDIV_SEL : STRING := "FALSE";
      IDIV_SEL : integer := 0;
      DYN_FBDIV_SEL : STRING := "FALSE";
      FBDIV_SEL : integer := 0;

      DYN_ODIVA_SEL : STRING := "FALSE";
      ODIVA_SEL : integer := 6;
      DYN_ODIVB_SEL : STRING := "FALSE";
      ODIVB_SEL : integer := 6;
      DYN_ODIVC_SEL : STRING := "FALSE";
      ODIVC_SEL : integer := 6;
      DYN_ODIVD_SEL : STRING := "FALSE";
      ODIVD_SEL : integer := 6;

      CLKOUTA_EN : STRING := "TRUE";
      CLKOUTB_EN : STRING := "TRUE";
      CLKOUTC_EN : STRING := "TRUE";
      CLKOUTD_EN : STRING := "TRUE";

      DYN_DTA_SEL : STRING := "FALSE";
      DYN_DTB_SEL : STRING := "FALSE";
      CLKOUTA_DT_DIR : bit := '1';
      CLKOUTB_DT_DIR : bit := '1';
      CLKOUTA_DT_STEP : integer := 0;
      CLKOUTB_DT_STEP : integer := 0;

      CLKA_IN_SEL  : bit_vector := "00";
      CLKA_OUT_SEL : bit := '0';
      CLKB_IN_SEL  : bit_vector := "00";
      CLKB_OUT_SEL : bit := '0';
      CLKC_IN_SEL  : bit_vector := "00";
      CLKC_OUT_SEL : bit := '0';
      CLKD_IN_SEL  : bit_vector := "00";
      CLKD_OUT_SEL : bit := '0';

      CLKFB_SEL : STRING := "INTERNAL";

      DYN_DPA_EN : STRING := "FALSE";

      DYN_PSB_SEL : STRING := "FALSE";
      DYN_PSC_SEL : STRING := "FALSE";
      DYN_PSD_SEL : STRING := "FALSE";

      PSB_COARSE : integer := 0;
      PSB_FINE : integer := 0;
      PSC_COARSE : integer := 0;
      PSC_FINE : integer := 0;
      PSD_COARSE : integer := 0;
      PSD_FINE : integer := 0;

      DTMS_ENB : STRING := "FALSE";
      DTMS_ENC : STRING := "FALSE";
      DTMS_END : STRING := "FALSE";

      RESET_I_EN : STRING := "FALSE";
      RESET_S_EN : STRING := "FALSE";

      DYN_ICP_SEL : STRING := "FALSE";
      ICP_SEL : std_logic_vector(4 downto 0) := "XXXXX";
      DYN_RES_SEL : STRING := "FALSE";
      LPR_REF : std_logic_vector(6 downto 0) := "XXXXXXX"
      );
    PORT(
      CLKIN : IN std_logic;
      CLKFB : IN std_logic:='0';
      RESET,RESET_P : IN std_logic:='0';
      RESET_I,RESET_S : IN std_logic:='0';
      IDSEL,FBDSEL : IN std_logic_vector(5 downto 0);
      ODSELA, ODSELB, ODSELC, ODSELD : IN std_logic_vector(6 downto 0);
      DTA, DTB : IN std_logic_vector(3 downto 0);
      ICPSEL : IN std_logic_vector(4 downto 0);
      LPFRES : IN std_logic_vector(2 downto 0);
      PSSEL : IN std_logic_vector(1 downto 0);
      PSDIR,PSPULSE : IN std_logic;
      ENCLKA,ENCLKB,ENCLKC,ENCLKD : IN std_logic;
      LOCK : OUT std_logic;
      CLKOUTA : OUT std_logic;
      CLKOUTB : OUT std_logic;
      CLKOUTC : OUT std_logic;
      CLKOUTD : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of PLLO : Component is true;

  COMPONENT OSC IS
    GENERIC (
      FREQ_DIV : integer := 100;
      DEVICE : string := "GW1N-4"
      );
    PORT (
      OSCOUT: OUT STD_LOGIC
      );
  end component;
  attribute syn_black_box of OSC : Component is true;

  COMPONENT OSCH IS
    GENERIC (
      FREQ_DIV : integer := 96
      );
    PORT (
      OSCOUT: OUT STD_LOGIC
      );
  end component;
  attribute syn_black_box of OSCH : Component is true;

  COMPONENT OSCF IS
    GENERIC (
      FREQ_DIV : integer := 96
      );
    PORT (
      OSCOUT: OUT STD_LOGIC;
      OSCOUT30M: OUT STD_LOGIC;
      OSCEN : IN STD_LOGIC
      );
  end component;
  attribute syn_black_box of OSCF : Component is true;

  COMPONENT OSCZ IS
    GENERIC (
      FREQ_DIV : integer := 100
      );
    PORT (
      OSCOUT: OUT STD_LOGIC;
      OSCEN : IN STD_LOGIC
      );
  end component;
  attribute syn_black_box of OSCZ : Component is true;

  COMPONENT OSCO is
    GENERIC (
      FREQ_DIV : integer := 100;
      REGULATOR_EN : bit := '0'
      );
    PORT (
      OSCOUT: OUT STD_LOGIC;
      OSCEN : IN STD_LOGIC
      );
  end COMPONENT;
  attribute syn_black_box of OSCO : Component is true;

  COMPONENT DCCG is
    GENERIC (
      DCC_MODE : bit_vector := "00";
      FCLKIN : REAL := 50.0
      );
    PORT (
      CLKOUT: OUT STD_LOGIC;
      CLKIN : IN STD_LOGIC
      );
  end COMPONENT;
  attribute syn_black_box of DCCG : Component is true;

  COMPONENT FLASH256KA is
    PORT(
      XADR : IN std_logic_vector(6 downto 0);
      YADR : IN std_logic_vector(5 downto 0);
      XE,YE,SE:IN std_logic;
      DIN : IN std_logic_vector(31 downto 0);
      ERASE,PROG,NVSTR: IN std_logic;
      SLEEP : IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end COMPONENT;
  attribute syn_black_box of FLASH256KA : Component is true;

  COMPONENT MIPI_DPHY_RX is
    GENERIC(
      ALIGN_BYTE : bit_vector := "10111000";
      MIPI_LANE0_EN  : bit := '0';
      MIPI_LANE1_EN  : bit := '0';
      MIPI_LANE2_EN  : bit := '0';
      MIPI_LANE3_EN  : bit := '0';
      MIPI_CK_EN  : bit := '1';
      SYNC_CLK_SEL : bit := '1'
      );
    PORT(
      D0LN_HSRXD, D1LN_HSRXD, D2LN_HSRXD, D3LN_HSRXD : OUT std_logic_vector(15 downto 0);
      D0LN_HSRXD_VLD,D1LN_HSRXD_VLD,D2LN_HSRXD_VLD,D3LN_HSRXD_VLD : OUT std_logic;
      DI_LPRX0_N, DI_LPRX0_P, DI_LPRX1_N, DI_LPRX1_P, DI_LPRX2_N, DI_LPRX2_P, DI_LPRX3_N, DI_LPRX3_P : OUT std_logic;
      DI_LPRXCK_N, DI_LPRXCK_P : OUT std_logic;
      RX_CLK_O : OUT std_logic;
      DESKEW_ERROR : OUT std_logic;
      CK_N, CK_P, RX0_N, RX0_P, RX1_N, RX1_P, RX2_N, RX2_P, RX3_N, RX3_P : INOUT std_logic;
      LPRX_EN_CK, LPRX_EN_D0, LPRX_EN_D1, LPRX_EN_D2, LPRX_EN_D3 : IN std_logic;
      HSRX_ODTEN_CK, HSRX_ODTEN_D0,  HSRX_ODTEN_D1, HSRX_ODTEN_D2, HSRX_ODTEN_D3 : IN std_logic;
      D0LN_HSRX_DREN,  D1LN_HSRX_DREN, D2LN_HSRX_DREN, D3LN_HSRX_DREN : IN std_logic;
      HSRX_EN_CK : IN std_logic;
      DESKEW_REQ : IN std_logic;
      HS_8BIT_MODE : IN std_logic;
      RX_CLK_1X : IN std_logic;
      RX_INVERT : IN std_logic;
      LALIGN_EN : IN std_logic;
      WALIGN_BY : IN std_logic;
      DO_LPTX0_N, DO_LPTX0_P, DO_LPTX1_N, DO_LPTX1_P, DO_LPTX2_N, DO_LPTX2_P, DO_LPTX3_N, DO_LPTX3_P : IN std_logic;
      DO_LPTXCK_N, DO_LPTXCK_P : IN std_logic;
      LPTX_EN_CK, LPTX_EN_D0, LPTX_EN_D1, LPTX_EN_D2, LPTX_EN_D3 : IN std_logic;
      BYTE_LENDIAN : IN std_logic;
      HSRX_STOP : IN std_logic;
      LPRX_ULP_LN0, LPRX_ULP_LN1, LPRX_ULP_LN2, LPRX_ULP_LN3, LPRX_ULP_CK : IN std_logic;
      PWRON,RESET : IN std_logic;
      DESKEW_LNSEL : IN std_logic_vector(2 downto 0);
      DESKEW_MTH : IN std_logic_vector(7 downto 0);
      DESKEW_OWVAL : IN std_logic_vector(6 downto 0);
      DRST_N : IN std_logic;
      FIFO_RD_STD : IN std_logic_vector(2 downto 0);
      ONE_BYTE0_MATCH : IN std_logic;
      WORD_LENDIAN : IN std_logic
      );
  end COMPONENT;
  attribute syn_black_box of MIPI_DPHY_RX : Component is true;
  attribute black_box_pad_pin of MIPI_DPHY_RX : Component is "CK_N, CK_P, RX0_N, RX0_P, RX1_N, RX1_P, RX2_N, RX2_P, RX3_N, RX3_P";

  COMPONENT CLKDIVG
    GENERIC(
      DIV_MODE : STRING := "2";
      GSREN : STRING := "false"
      );
    PORT(
      CLKIN : IN std_logic;
      RESETN : IN std_logic;
      CALIB : In std_logic;
      CLKOUT : OUT std_logic
      );
  end COMPONENT;
  attribute syn_black_box of CLKDIVG : Component is true;

  component GW_JTAG is
    port(
      tck_pad_i : in std_logic;
      tms_pad_i : in std_logic;
      tdi_pad_i : in std_logic;
      tdo_pad_o : out std_logic;
      tdo_er1_i : in std_logic;
      tdo_er2_i : in std_logic;
      tck_o : out std_logic;
      tdi_o : out std_logic;
      test_logic_reset_o : out std_logic;
      run_test_idle_er1_o : out std_logic;
      run_test_idle_er2_o : out std_logic;
      shift_dr_capture_dr_o : out std_logic;
      pause_dr_o : out std_logic;
      update_dr_o : out std_logic;
      enable_er1_o : out std_logic;
      enable_er2_o : out std_logic
      );
  end component;
  attribute syn_black_box of GW_JTAG : Component is true;

  component IDDR is
    GENERIC (
      Q0_INIT : bit := '0';
      Q1_INIT : bit := '0'
      );
    PORT (
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      D : IN std_logic;
      CLK: IN std_logic
      );
  end component;
  attribute syn_black_box of IDDR : Component is true;

  component IBUF is
    PORT (
      O : OUT std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of IBUF : component is true;

  component OBUF is
    PORT (
      O : OUT std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of OBUF : component is true;

  component TBUF is
    PORT (
      O : OUT std_logic;
      I : IN std_logic;
      OEN : IN std_logic
      );
  end component;
  attribute syn_black_box of TBUF : component is true;

  component IOBUF is
    PORT (
      O  : OUT   std_logic;
      IO : INOUT std_logic;
      I  : IN    std_logic;
      OEN : IN    std_logic
      );
  end component;
  attribute syn_black_box of IOBUF : component is true;

  component IDDRC is
    GENERIC (
      Q0_INIT : bit := '0';
      Q1_INIT : bit := '0'
      );
    PORT (
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      D : IN std_logic;
      CLEAR: IN std_logic;
      CLK: IN std_logic
      );
  end component;
  attribute syn_black_box of IDDRC : component is true;

  component ODDR is
    GENERIC (
      TXCLK_POL : bit := '0';
      CONSTANT INIT : std_logic := '0'
      );
    PORT (
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      D0 : IN std_logic;
      D1 : IN std_logic;
      TX : IN std_logic;
      CLK : IN std_logic
      );
  end component;
  attribute syn_black_box of ODDR : component is true;

  component ODDRC is
    GENERIC (
      TXCLK_POL : bit := '0';
      CONSTANT INIT : std_logic := '0'
      );
    PORT (
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      D0 : IN std_logic;
      D1: IN std_logic;
      TX: IN std_logic;
      CLK : IN std_logic;
      CLEAR: IN std_logic
      );
  end component;
  attribute syn_black_box of ODDRC : component is true;

  component IDES4 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D : IN std_logic;
      RESET : IN std_logic;
      CALIB : IN std_logic;
      FCLK : IN std_logic;
      PCLK : IN std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      Q2 : OUT std_logic;
      Q3 : OUT std_logic
      );
  end component;
  attribute syn_black_box of IDES4 : component is true;

  component IVIDEO is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );

    PORT (
      D : IN std_logic;
      RESET : IN std_logic;
      CALIB : IN std_logic;
      FCLK : IN std_logic;
      PCLK : IN std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      Q2 : OUT std_logic;
      Q3 : OUT std_logic;
      Q4 : OUT std_logic;
      Q5 : OUT std_logic;
      Q6 : OUT std_logic
      );
  end component;
  attribute syn_black_box of IVIDEO : component is true;

  component IDES8 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D,RESET : IN std_logic;
      CALIB : IN std_logic;
      FCLK,PCLK : IN std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      Q2 : OUT std_logic;
      Q3 : OUT std_logic;
      Q4 : OUT std_logic;
      Q5 : OUT std_logic;
      Q6 : OUT std_logic;
      Q7 : OUT std_logic
      );
  end component;
  attribute syn_black_box of IDES8 : component is true;

  component IDES10 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D,RESET : IN std_logic;
      CALIB : IN std_logic;
      FCLK,PCLK : IN std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      Q2 : OUT std_logic;
      Q3 : OUT std_logic;
      Q4 : OUT std_logic;
      Q5 : OUT std_logic;
      Q6 : OUT std_logic;
      Q7 : OUT std_logic;
      Q8 : OUT std_logic;
      Q9 : OUT std_logic
      );
  end component;
  attribute syn_black_box of IDES10 : component is true;

  component IDES16 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D,RESET : IN std_logic;
      CALIB : IN std_logic;
      FCLK,PCLK : IN std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      Q2 : OUT std_logic;
      Q3 : OUT std_logic;
      Q4 : OUT std_logic;
      Q5 : OUT std_logic;
      Q6 : OUT std_logic;
      Q7 : OUT std_logic;
      Q8 : OUT std_logic;
      Q9 : OUT std_logic;
      Q10 : OUT std_logic;
      Q11 : OUT std_logic;
      Q12 : OUT std_logic;
      Q13 : OUT std_logic;
      Q14 : OUT std_logic;
      Q15 : OUT std_logic
      );
  end component;
  attribute syn_black_box of IDES16 : component is true;

  component OSER4 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true";
      HWL : string := "false";
      TXCLK_POL : bit := '0'
      );
    PORT (
      D0 : in std_logic;
      D1 : in std_logic;
      D2 : in std_logic;
      D3 : in std_logic;
      TX0 : in std_logic;
      TX1 : in std_logic;
      PCLK : in std_logic;
      RESET : in std_logic;
      FCLK : in std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic
      );
  end component;
  attribute syn_black_box of OSER4 : component is true;

  component OVIDEO is
    GENERIC(
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D0 : in std_logic;
      D1 : in std_logic;
      D2 : in std_logic;
      D3 : in std_logic;
      D4 : in std_logic;
      D5 : in std_logic;
      D6 : in std_logic;
      PCLK : in std_logic;
      RESET : in std_logic;
      FCLK : in std_logic;
      Q : OUT std_logic
      );
  end component;
  attribute syn_black_box of OVIDEO : component is true;

  component OSER8 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true";
      HWL : string := "false";
      TXCLK_POL : bit := '0'
      );
    PORT (
      D0 : in std_logic;
      D1 : in std_logic;
      D2 : in std_logic;
      D3 : in std_logic;
      D4 : in std_logic;
      D5 : in std_logic;
      D6 : in std_logic;
      D7 : in std_logic;
      TX0 : in std_logic;
      TX1 : in std_logic;
      TX2 : in std_logic;
      TX3 : in std_logic;
      PCLK : in std_logic;
      RESET : in std_logic;
      FCLK : in std_logic;
      Q0 : OUT std_logic;
      Q1 : OUT std_logic
      );
  end component;
  attribute syn_black_box of OSER8 : component is true;

  component OSER10 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D0 : in std_logic;
      D1 : in std_logic;
      D2 : in std_logic;
      D3 : in std_logic;
      D4 : in std_logic;
      D5 : in std_logic;
      D6 : in std_logic;
      D7 : in std_logic;
      D8 : in std_logic;
      D9 : in std_logic;
      PCLK : in std_logic;
      RESET : in std_logic;
      FCLK : in std_logic;
      Q : OUT std_logic
      );
  end component;
  attribute syn_black_box of OSER10 : component is true;

  component OSER16 is
    GENERIC (
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D0 : in std_logic;
      D1 : in std_logic;
      D2 : in std_logic;
      D3 : in std_logic;
      D4 : in std_logic;
      D5 : in std_logic;
      D6 : in std_logic;
      D7 : in std_logic;
      D8 : in std_logic;
      D9 : in std_logic;
      D10 : in std_logic;
      D11 : in std_logic;
      D12 : in std_logic;
      D13 : in std_logic;
      D14 : in std_logic;
      D15 : in std_logic;
      PCLK : in std_logic;
      RESET : in std_logic;
      FCLK : in std_logic;
      Q : OUT std_logic
      );
  end component;
  attribute syn_black_box of OSER16 : component is true;

  component IODELAY is
    GENERIC (  C_STATIC_DLY : integer := 0);
    PORT (
      DI : IN std_logic;
      SDTAP : IN std_logic;
      SETN : IN std_logic;
      VALUE : IN std_logic;
      DO : OUT std_logic;
      DF : OUT std_logic
      );
  end component;
  attribute syn_black_box of IODELAY : component is true;

  component IEM is
    GENERIC(
      WINSIZE : string := "SMALL";
      GSREN : string := "false";
      LSREN : string := "true"
      );
    PORT (
      D : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      MCLK: in std_logic;
      LAG : out std_logic;
      LEAD : out std_logic
      );
  end component;
  attribute syn_black_box of IEM : component is true;

  component BUFG is
    PORT(
      O : out std_logic;
      I : in std_logic
      );
  end component;
  attribute syn_black_box of BUFG : component is true;

  component BUFS is
    PORT (
      O : out std_logic;
      I : in std_logic
      );
  end component;
  attribute syn_black_box of BUFS : component is true;

  component TLVDS_IBUF is
    PORT(
      O : OUT std_logic;
      I : IN std_logic;
      IB : IN std_logic
      );
  end component;
  attribute syn_black_box of TLVDS_IBUF : component is true;

  component TLVDS_OBUF is
    PORT(
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of TLVDS_OBUF : component is true;

  component TLVDS_TBUF is
    PORT (
      O  : OUT   std_logic;
      OB : OUT std_logic;
      I  : IN    std_logic;
      OEN : IN    std_logic
      );
  end component;
  attribute syn_black_box of TLVDS_TBUF : component is true;

  component TLVDS_IOBUF is
    PORT (
      O  : OUT   std_logic;
      IOB : INOUT std_logic;
      IO : INOUT std_logic;
      I  : IN    std_logic;
      OEN : IN    std_logic
      );
  end component;
  attribute syn_black_box of TLVDS_IOBUF : component is true;

  component ELVDS_IBUF is
    PORT(
      O : OUT std_logic;
      I : IN std_logic;
      IB : IN std_logic
      );
  end component;
  attribute syn_black_box of ELVDS_IBUF : component is true;

  component ELVDS_OBUF is
    PORT(
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of ELVDS_OBUF : component is true;

  component ELVDS_TBUF is
    PORT (
      O  : OUT   std_logic;
      OB : OUT std_logic;
      I  : IN    std_logic;
      OEN : IN    std_logic
      );
  end component;
  attribute syn_black_box of ELVDS_TBUF : component is true;

  component ELVDS_IOBUF is
    PORT (
      O  : OUT   std_logic;
      IOB : INOUT std_logic;
      IO : INOUT std_logic;
      I  : IN    std_logic;
      OEN : IN    std_logic
      );
  end component;
  attribute syn_black_box of ELVDS_IOBUF : component is true;

  component MIPI_IBUF is
    PORT (
      OH, OL, OB : OUT std_logic;
      IO, IOB : INOUT std_logic;
      I, IB : IN std_logic;
      OEN, OENB, HSREN : IN std_logic
      );
  end component;
  attribute syn_black_box of MIPI_IBUF : component is true;

  component MIPI_IBUF_HS is
    PORT (
      OH : OUT std_logic;
      I : IN std_logic;
      IB : IN std_logic
      );
  end component;
  attribute syn_black_box of MIPI_IBUF_HS : component is true;

  component MIPI_IBUF_LP is
    PORT (
      OL : OUT std_logic;
      OB : OUT std_logic;
      IB : IN std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of MIPI_IBUF_LP : component is true;

  component I3C_IOBUF is
    PORT (
      O  : OUT   std_logic;
      IO : INOUT std_logic;
      I  : IN    std_logic;
      MODESEL : IN    std_logic
      );
  end component;
  attribute syn_black_box of I3C_IOBUF : component is true;

  component PADD18 is
    generic(
      AREG : bit := '0';
      BREG : bit := '0';
      SOREG : bit := '0';
      ADD_SUB : bit := '0';
      PADD_RESET_MODE : string := "SYNC";
      BSEL_MODE : bit := '1'
      );

    port(
      A : in std_logic_vector(17 downto 0);
      B : in std_logic_vector(17 downto 0);
      ASEL : in std_logic;
      CE,CLK,RESET : in std_logic;
      SI,SBI : in std_logic_vector(17 downto 0);
      SO,SBO : out std_logic_vector(17 downto 0);
      DOUT : out std_logic_vector(17 downto 0)
      );
  end component;
  attribute syn_black_box of PADD18 : component is true;

  component PADD9 is
    generic(
      AREG : bit := '0';
      BREG : bit := '0';
      SOREG : bit := '0';
      ADD_SUB : bit := '0';
      PADD_RESET_MODE : string := "SYNC";
      BSEL_MODE : bit := '1'
      );

    port(
      A : in std_logic_vector(8 downto 0);
      B : in std_logic_vector(8 downto 0);
      ASEL : in std_logic;
      CE,CLK,RESET : in std_logic;
      SI,SBI : in std_logic_vector(8 downto 0);
      SO,SBO : out std_logic_vector(8 downto 0);
      DOUT : out std_logic_vector(8 downto 0)
      );
  end component;
  attribute syn_black_box of PADD9 : component is true;

  component MULT9X9 is
    generic(
      AREG :  bit := '0';
      BREG :  bit := '0';
      OUT_REG :  bit := '0';
      PIPE_REG :  bit := '0';
      ASIGN_REG :  bit := '0';
      BSIGN_REG :  bit := '0';
      SOA_REG :  bit := '0';
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A,SIA : in std_logic_vector(8 downto 0);
      B,SIB : in std_logic_vector(8 downto 0);
      ASIGN, BSIGN : in std_logic;
      ASEL,BSEL : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      DOUT : out std_logic_vector(17 downto 0);
      SOA,SOB : out std_logic_vector(8 downto 0)
      );
  end component;
  attribute syn_black_box of MULT9X9 : component is true;

  component MULT18X18 is
    generic(
      AREG :  bit := '0';
      BREG :  bit := '0';
      OUT_REG :  bit := '0';
      PIPE_REG :  bit := '0';
      ASIGN_REG :  bit := '0';
      BSIGN_REG :  bit := '0';
      SOA_REG :  bit := '0';
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A,SIA : in std_logic_vector(17 downto 0);
      B,SIB : in std_logic_vector(17 downto 0);
      ASIGN, BSIGN : in std_logic;
      ASEL,BSEL : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      DOUT : out std_logic_vector(35 downto 0);
      SOA,SOB : out std_logic_vector(17 downto 0)
      );
  end component;
  attribute syn_black_box of MULT18X18 : component is true;

  component MULT36X36 is
    generic(
      AREG :  bit := '0';
      BREG :  bit := '0';
      OUT0_REG :  bit := '0';
      OUT1_REG :  bit := '0';
      PIPE_REG :  bit := '0';
      ASIGN_REG :  bit := '0';
      BSIGN_REG :  bit := '0';
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A : in std_logic_vector(35 downto 0);
      B : in std_logic_vector(35 downto 0);
      ASIGN, BSIGN : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      DOUT : out std_logic_vector(71 downto 0)
      );
  end component;
  attribute syn_black_box of MULT36X36 : component is true;

  component MULTALU36X18 is
    generic(
      AREG :  bit := '0';
      BREG :  bit := '0';
      CREG :  bit := '0';
      OUT_REG :  bit := '0';
      PIPE_REG :  bit := '0';
      ASIGN_REG :  bit := '0';
      BSIGN_REG :  bit := '0';
      ACCLOAD_REG0 : bit := '0';
      ACCLOAD_REG1 : bit := '0';
      MULTALU36X18_MODE : integer := 0;
      C_ADD_SUB : bit := '0';
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A : in std_logic_vector(17 downto 0);
      B : in std_logic_vector(35 downto 0);
      C : in std_logic_vector(53 downto 0);
      ASIGN, BSIGN, ACCLOAD : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      CASI : in std_logic_vector(54 downto 0);
      DOUT : out std_logic_vector(53 downto 0);
      CASO : out std_logic_vector(54 downto 0)
      );
  end component;
  attribute syn_black_box of MULTALU36X18 : component is true;

  component MULTADDALU18X18 is
    generic(
      A0REG : bit := '0';
      B0REG : bit := '0';
      A1REG : bit := '0';
      B1REG : bit := '0';
      CREG : bit := '0';
      OUT_REG : bit := '0';
      PIPE0_REG : bit := '0';
      PIPE1_REG : bit := '0';
      ASIGN0_REG : bit := '0';
      BSIGN0_REG : bit := '0';
      ASIGN1_REG : bit := '0';
      BSIGN1_REG : bit := '0';
      ACCLOAD_REG0 : bit := '0';
      ACCLOAD_REG1 : bit := '0';
      SOA_REG : bit := '0';
      B_ADD_SUB : bit := '0';
      C_ADD_SUB : bit := '0';
      MULTADDALU18X18_MODE : integer := 0;
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A0,A1 : in std_logic_vector(17 downto 0);
      B0,B1 : in std_logic_vector(17 downto 0);
      SIA,SIB : in std_logic_vector(17 downto 0);
      C : in std_logic_vector(53 downto 0);
      ASIGN,BSIGN : in std_logic_vector(1 downto 0);
      ASEL,BSEL : in std_logic_vector(1 downto 0);
      CASI : in std_logic_vector(54 downto 0);
      ACCLOAD : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      DOUT : out std_logic_vector(53 downto 0);
      SOA,SOB : out std_logic_vector(17 downto 0);
      CASO : out std_logic_vector(54 downto 0)
      );
  end component;
  attribute syn_black_box of MULTADDALU18X18 : component is true;

  component MULTALU18X18 is
    generic(
      AREG : bit := '0';
      BREG : bit := '0';
      CREG : bit := '0';
      DREG : bit := '0';
      OUT_REG : bit := '0';
      PIPE_REG : bit := '0';
      ASIGN_REG : bit := '0';
      BSIGN_REG : bit := '0';
      DSIGN_REG : bit := '0';
      ACCLOAD_REG0 : bit := '0';
      ACCLOAD_REG1 : bit := '0';
      B_ADD_SUB : bit := '0';
      C_ADD_SUB : bit := '0';
      MULTALU18X18_MODE : integer := 0;
      MULT_RESET_MODE : string := "SYNC"
      );

    port (
      A : in std_logic_vector(17 downto 0);
      B : in std_logic_vector(17 downto 0);
      C, D : in std_logic_vector(53 downto 0);
      ASIGN, BSIGN : in std_logic;
      CASI : in std_logic_vector(54 downto 0);
      ACCLOAD,DSIGN : in std_logic;
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      DOUT : out std_logic_vector(53 downto 0);
      CASO : out std_logic_vector(54 downto 0)
      );
  end component;
  attribute syn_black_box of MULTALU18X18 : component is true;

  component ALU54D is
    generic(
      AREG : bit := '0';
      BREG : bit := '0';
      ASIGN_REG : bit := '0';
      BSIGN_REG : bit := '0';
      ACCLOAD_REG : bit := '0';
      OUT_REG : bit := '0';
      B_ADD_SUB : bit := '0';
      C_ADD_SUB : bit := '0';
      ALUD_MODE : integer := 0;
      ALU_RESET_MODE : string := "SYNC"
      );
    port (
      A : in std_logic_vector (53 downto 0);
      B : in std_logic_vector (53 downto 0);
      CE : in std_logic;
      CLK : in std_logic;
      RESET : in std_logic;
      ASIGN,BSIGN : in std_logic;
      ACCLOAD : in std_logic;
      CASI : in std_logic_vector (54 downto 0);
      DOUT : out std_logic_vector (53 downto 0);
      CASO : out std_logic_vector (54 downto 0)
      );
  end component;
  attribute syn_black_box of ALU54D : component is true;

  component PLL is
    GENERIC(
      FCLKIN : STRING := "100.0";
      DEVICE : STRING := "GW1N-4";
      DYN_IDIV_SEL : STRING := "false";
      IDIV_SEL : integer := 0;
      DYN_FBDIV_SEL : STRING := "false";
      FBDIV_SEL : integer := 0;
      DYN_ODIV_SEL : STRING := "false";
      ODIV_SEL : integer := 8;
      PSDA_SEL : STRING := "0000";
      DYN_DA_EN : STRING := "false";
      DUTYDA_SEL : STRING := "1000";
      CLKOUT_FT_DIR : bit := '1';
      CLKOUTP_FT_DIR : bit := '1';
      CLKOUT_DLY_STEP : integer := 0;
      CLKOUTP_DLY_STEP : integer := 0;

      CLKOUTD3_SRC : STRING := "CLKOUT";
      CLKFB_SEL : STRING := "internal";
      CLKOUT_BYPASS : STRING := "false";
      CLKOUTP_BYPASS : STRING := "false";
      CLKOUTD_BYPASS : STRING := "false";
      CLKOUTD_SRC : STRING := "CLKOUT";
      DYN_SDIV_SEL : integer := 2
      );
    PORT(
      CLKIN : IN std_logic;
      CLKFB : IN std_logic:='0';
      IDSEL : In std_logic_vector(5 downto 0);
      FBDSEL : In std_logic_vector(5 downto 0);
      ODSEL : In std_logic_vector(5 downto 0);
      RESET : in std_logic:='0';
      RESET_P : in std_logic:='0';
      RESET_I :in std_logic:='0';
      RESET_S : in std_logic :='0';
      PSDA,FDLY : In std_logic_vector(3 downto 0);
      DUTYDA : In std_logic_vector(3 downto 0);
      LOCK : OUT std_logic;
      CLKOUT : OUT std_logic;
      CLKOUTD : out std_logic;
      CLKOUTP : out std_logic;
      CLKOUTD3 : out std_logic
      );
  end component;
  attribute syn_black_box of PLL : component is true;

  component DHCEN is
    PORT (
      CLKOUT : OUT std_logic;
      CE : IN std_logic;
      CLKIN : IN std_logic
      );
  end component;
  attribute syn_black_box of DHCEN : component is true;

  component DLL is
    GENERIC(
      DLL_FORCE : integer := 0;
      DIV_SEL : bit := '1';
      CODESCAL : STRING := "000";
      SCAL_EN : STRING := "true"
      );
    PORT(
      CLKIN:IN std_logic:='0';
      STOP: In std_logic:='0';
      RESET : In std_logic:='0';
      UPDNCNTL : In std_logic:='0';
      LOCK : OUT std_logic;
      STEP : OUT std_logic_vector(7 downto 0)
      );
  end component;
  attribute syn_black_box of DLL : component is true;

  component DLLDLY is
    GENERIC(
      DLL_INSEL : bit := '1';
      DLY_SIGN : bit := '0';
      DLY_ADJ : integer := 0
      );
    PORT(
      DLLSTEP : IN std_logic_vector(7 downto 0);
      CLKIN:IN std_logic;
      DIR,LOADN,MOVE: In std_logic;
      CLKOUT : OUT std_logic;
      FLAG : OUT std_logic
      );
  end component;
  attribute syn_black_box of DLLDLY : component is true;

  component FLASH96K is
    PORT(
      RA,CA,PA : IN std_logic_vector(5 downto 0);
      MODE : IN std_logic_vector(3 downto 0);
      ACLK,PW,RESET,PE,OE:IN std_logic;
      SEQ,RMODE,WMODE : IN std_logic_vector(1 downto 0);
      RBYTESEL,WBYTESEL : IN std_logic_vector(1 downto 0);
      DIN : IN std_logic_vector(31 downto 0);
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end component;
  attribute syn_black_box of FLASH96K : component is true;

  component FLASH608K is
    PORT(
      XADR : IN std_logic_vector(8 downto 0);
      YADR : IN std_logic_vector(5 downto 0);
      XE,YE,SE:IN std_logic;
      DIN : IN std_logic_vector(31 downto 0);
      ERASE,PROG,NVSTR: IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end component;
  attribute syn_black_box of FLASH608K : component is true;

  component DCS is
    GENERIC (
      DCS_MODE : string := "RISING"
      );
    PORT (
      CLK0 : IN std_logic;
      CLK1 : IN std_logic;
      CLK2 : IN std_logic;
      CLK3 : IN std_logic;
      CLKSEL : IN std_logic_vector(3 downto 0);
      SELFORCE : IN std_logic;
      CLKOUT : OUT std_logic
      );
  end component;
  attribute syn_black_box of DCS : component is true;

  component DQCE is
    PORT (
      CLKOUT : OUT std_logic;
      CE : IN std_logic;
      CLKIN : IN std_logic
      );
  end component;
  attribute syn_black_box of DQCE : component is true;

  component FLASH128K is
    PORT(
      ADDR : IN std_logic_vector(14 downto 0);
      DIN : IN std_logic_vector(31 downto 0);
      CS,AE,OE : IN std_logic;
      PCLK : IN std_logic;
      PROG,SERA,MASE :IN std_logic;
      IFREN,RESETN,NVSTR: IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0);
      TBIT : OUT std_logic
      );
  end component;
  attribute syn_black_box of FLASH128K : component is true;

  component MCU is
    PORT(
      FCLK : IN std_logic;
      PORESETN : IN std_logic;
      SYSRESETN : IN std_logic;
      RTCSRCCLK : IN std_logic;
      IOEXPOUTPUTO : OUT std_logic_vector(15 downto 0);
      IOEXPOUTPUTENO : OUT std_logic_vector(15 downto 0);
      IOEXPINPUTI : IN std_logic_vector(15 downto 0);
      UART0TXDO : OUT std_logic;
      UART1TXDO : OUT std_logic;
      UART0BAUDTICK : OUT std_logic;
      UART1BAUDTICK : OUT std_logic;
      UART0RXDI : IN std_logic;
      UART1RXDI : IN std_logic;
      INTMONITOR : OUT std_logic;
      MTXHRESETN : OUT std_logic;
      SRAM0ADDR : OUT std_logic_vector(12 downto 0);
      SRAM0WREN : OUT std_logic_vector(3 downto 0);
      SRAM0WDATA : OUT std_logic_vector(31 downto 0);
      SRAM0CS : OUT std_logic;
      SRAM0RDATA : in std_logic_vector(31 downto 0);

      TARGFLASH0HSEL : OUT std_logic;
      TARGFLASH0HADDR : OUT std_logic_vector(28 downto 0);
      TARGFLASH0HTRANS : OUT std_logic_vector(1 downto 0);
      TARGFLASH0HWRITE : OUT std_logic;
      TARGFLASH0HSIZE : OUT std_logic_vector(2 downto 0);
      TARGFLASH0HBURST : OUT std_logic_vector(2 downto 0);
      TARGFLASH0HPROT : OUT std_logic_vector(3 downto 0);
      TARGFLASH0MEMATTR : OUT std_logic_vector(1 downto 0);
      TARGFLASH0EXREQ : OUT std_logic;
      TARGFLASH0HMASTER : OUT std_logic_vector(3 downto 0);
      TARGFLASH0HWDATA : OUT std_logic_vector(31 downto 0);
      TARGFLASH0HMASTLOCK : OUT std_logic;
      TARGFLASH0HREADYMUX : OUT std_logic;
      TARGFLASH0HAUSER : OUT std_logic;
      TARGFLASH0HWUSER : OUT std_logic_vector(3 downto 0);
      TARGFLASH0HRDATA : IN std_logic_vector(31 downto 0);
      TARGFLASH0HRUSER : IN std_logic_vector(2 downto 0);
      TARGFLASH0HRESP : IN std_logic;
      TARGFLASH0EXRESP : IN std_logic;
      TARGFLASH0HREADYOUT : IN std_logic;

      TARGEXP0HSEL : OUT std_logic;
      TARGEXP0HADDR : OUT std_logic_vector(31 downto 0);
      TARGEXP0HTRANS : OUT std_logic_vector(1 downto 0);
      TARGEXP0HWRITE : OUT std_logic;
      TARGEXP0HSIZE : OUT std_logic_vector(2 downto 0);
      TARGEXP0HBURST : OUT std_logic_vector(2 downto 0);
      TARGEXP0HPROT : OUT std_logic_vector(3 downto 0);
      TARGEXP0MEMATTR : OUT std_logic_vector(1 downto 0);
      TARGEXP0EXREQ : OUT std_logic;
      TARGEXP0HMASTER : OUT std_logic_vector(3 downto 0);
      TARGEXP0HWDATA : OUT std_logic_vector(31 downto 0);
      TARGEXP0HMASTLOCK : OUT std_logic;
      TARGEXP0HREADYMUX : OUT std_logic;
      TARGEXP0HAUSER : OUT std_logic;
      TARGEXP0HWUSER : OUT std_logic_vector(3 downto 0);
      TARGEXP0HRDATA : IN std_logic_vector(31 downto 0);
      TARGEXP0HREADYOUT : IN std_logic;
      TARGEXP0HRESP : IN std_logic;
      TARGEXP0EXRESP : IN std_logic;
      TARGEXP0HRUSER : IN std_logic_vector(2 downto 0);

      INITEXP0HRDATA : OUT std_logic_vector(31 downto 0);
      INITEXP0HREADY : OUT std_logic;
      INITEXP0HRESP : OUT std_logic;
      INITEXP0EXRESP : OUT std_logic;
      INITEXP0HRUSER : OUT std_logic_vector(2 downto 0);
      INITEXP0HSEL : IN std_logic;
      INITEXP0HADDR : IN std_logic_vector(31 downto 0);
      INITEXP0HTRANS : IN std_logic_vector(1 downto 0);
      INITEXP0HWRITE : IN std_logic;
      INITEXP0HSIZE : IN std_logic_vector(2 downto 0);
      INITEXP0HBURST : IN std_logic_vector(2 downto 0);
      INITEXP0HPROT : IN std_logic_vector(3 downto 0);
      INITEXP0MEMATTR : IN std_logic_vector(1 downto 0);
      INITEXP0EXREQ : IN std_logic;
      INITEXP0HMASTER : IN std_logic_vector(3 downto 0);
      INITEXP0HWDATA : IN std_logic_vector(31 downto 0);
      INITEXP0HMASTLOCK : IN std_logic;
      INITEXP0HAUSER : IN std_logic;
      INITEXP0HWUSER : IN std_logic_vector(3 downto 0);

      APBTARGEXP2PSTRB : OUT std_logic_vector(3 downto 0);
      APBTARGEXP2PPROT : OUT std_logic_vector(2 downto 0);
      APBTARGEXP2PSEL : OUT std_logic;
      APBTARGEXP2PENABLE : OUT std_logic;
      APBTARGEXP2PADDR : OUT std_logic_vector(11 downto 0);
      APBTARGEXP2PWRITE : OUT std_logic;
      APBTARGEXP2PWDATA : OUT std_logic_vector(31 downto 0);
      APBTARGEXP2PRDATA : IN std_logic_vector(31 downto 0);
      APBTARGEXP2PREADY : IN std_logic;
      APBTARGEXP2PSLVERR : IN std_logic;

      MTXREMAP : IN std_logic_vector(3 downto 0);

      DAPSWDO : OUT std_logic;
      DAPSWDOEN : OUT std_logic;
      DAPTDO : OUT std_logic;
      DAPJTAGNSW : OUT std_logic;
      DAPNTDOEN : OUT std_logic;
      DAPSWDITMS : IN std_logic;
      DAPTDI : IN std_logic;
      DAPNTRST : IN std_logic;
      DAPSWCLKTCK : IN std_logic;

      TPIUTRACEDATA : OUT std_logic_vector(3 downto 0);
      TPIUTRACESWO : OUT std_logic;
      TPIUTRACECLK : OUT std_logic;
      FLASHERR : IN std_logic;
      FLASHINT : IN std_logic
      );
  end component;
  attribute syn_black_box of MCU : component is true;

  component USB20_PHY is
    GENERIC(
      DATABUS16_8 : bit := '0';
      ADP_PRBEN : bit := '0';
      TEST_MODE : bit_vector := X"00000";
      HSDRV1 : bit := '0';
      HSDRV0 : bit := '0';
      CLK_SEL : bit := '0';
      M : bit_vector := X"0000";
      N : bit_vector := X"101000";
      C : bit_vector := X"01";
      FOC_LOCK : bit := '0'

      );
    PORT(
      DATAOUT : OUT std_logic_vector(15 downto 0);
      TXREADY : OUT std_logic;
      RXACTIVE : OUT std_logic;
      RXVLD : OUT std_logic;
      RXVLDH : OUT std_logic;
      CLK : OUT std_logic;
      RXERROR : OUT std_logic;
      LINESTATE : OUT std_logic_vector(1 downto 0);
      DP : INOUT std_logic;
      DM : INOUT std_logic;
      DATAIN : IN std_logic_vector(15 downto 0);
      TXVLD : IN std_logic;
      TXVLDH : IN std_logic;
      RESET : IN std_logic;
      SUSPENDM : IN std_logic;
      XCVRSEL : IN std_logic_vector(1 downto 0);
      TERMSEL : IN std_logic;
      OPMODE : IN std_logic_vector(1 downto 0);

      HOSTDIS : OUT std_logic;
      IDDIG : OUT std_logic;
      ADPPRB : OUT std_logic;
      ADPSNS : OUT std_logic;
      SESSVLD : OUT std_logic;
      VBUSVLD : OUT std_logic;
      RXDP : OUT std_logic;
      RXDM : OUT std_logic;
      RXRCV : OUT std_logic;
      IDPULLUP : IN std_logic;
      DPPD : IN std_logic;
      DMPD : IN std_logic;
      CHARGVBUS : IN std_logic;
      DISCHARGVBUS : IN std_logic;
      TXBITSTUFFEN : IN std_logic;
      TXBITSTUFFENH : IN std_logic;
      TXENN : IN std_logic;
      TXDAT : IN std_logic;
      TXSE0 : IN std_logic;
      FSLSSERIAL : IN std_logic;
      LBKERR : OUT std_logic;
      CLKRDY : OUT std_logic;
      INTCLK : IN std_logic;
      ID : INOUT std_logic;
      VBUS : INOUT std_logic;
      REXT : INOUT std_logic;
      XIN : IN std_logic;
      XOUT : INOUT std_logic;
      CLK480PAD : OUT std_logic;
      TEST : IN std_logic;
      SCANOUT1 : OUT std_logic;
      SCANOUT2 : OUT std_logic;
      SCANOUT3 : OUT std_logic;
      SCANOUT4 : OUT std_logic;
      SCANOUT5 : OUT std_logic;
      SCANOUT6 : OUT std_logic;
      SCANCLK : IN std_logic;
      SCANEN : IN std_logic;
      SCANMODE : IN std_logic;
      TRESETN : IN std_logic;
      SCANIN1 : IN std_logic;
      SCANIN2 : IN std_logic;
      SCANIN3 : IN std_logic;
      SCANIN4 : IN std_logic;
      SCANIN5 : IN std_logic;
      SCANIN6 : IN std_logic

      );
  end component;
  attribute syn_black_box of USB20_PHY : component is true;

  component ADC is
    GENERIC(
      VREF_EN : bit := '0';
      VREF_SEL : bit_vector := X"000"
      );
    PORT(
      CH : IN std_logic_vector(7 downto 0);
      SEL : IN std_logic_vector(2 downto 0);
      CLK,PD,SOC : IN std_logic;
      VREF : IN std_logic;
      EOC : OUT std_logic;
      ADOUT : OUT std_logic_vector(11 downto 0)
      );
  end component;
  attribute syn_black_box of ADC : component is true;

  component FLASH96KA is
    PORT(
      XADR : IN std_logic_vector(5 downto 0);
      YADR : IN std_logic_vector(5 downto 0);
      XE,YE,SE: IN std_logic;
      DIN : IN std_logic_vector(31 downto 0);
      ERASE,PROG,NVSTR: IN std_logic;
      SLEEP : IN std_logic;
      DOUT : OUT std_logic_vector(31 downto 0)
      );
  end component;
  attribute syn_black_box of FLASH96KA : component is true;

end components;
