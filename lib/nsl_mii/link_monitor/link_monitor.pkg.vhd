library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, work, nsl_logic;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use work.link.all;
use work.flit.all;
use nsl_logic.bool.all;

package link_monitor is
  
  type phy_type_t is (
    PHY_DP83xxx,
    PHY_RTL8211F,
    PHY_LAN8710
    );

  subtype phy_reg_addr_t is unsigned(4 downto 0);
  type phy_reg_addr_vector is array (integer range <>) of phy_reg_addr_t;
  constant phy_reg_bmcr_c : phy_reg_addr_t := "00000";
  constant phy_reg_bmsr_c : phy_reg_addr_t := "00001";
  constant phy_reg_anar_c : phy_reg_addr_t := "00100";
  constant phy_reg_lpar_c : phy_reg_addr_t := "00101";
  constant phy_reg_gsr_c  : phy_reg_addr_t := "01111";
  constant phy_reg_gcr_c  : phy_reg_addr_t := "01001";
  constant phy_reg_gst1_c : phy_reg_addr_t := "01010";

  subtype phy_reg_value_t is unsigned(15 downto 0);
  type phy_reg_value_vector is array (integer range <>) of phy_reg_addr_t;

  component link_monitor_smi is
    generic(
      refresh_hz_c : real := 2.0;
      clock_i_hz_c: natural;
      phy_type_c: phy_type_t
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      irq_n_i    : in std_ulogic := '0';

      phyad_i : in unsigned(4 downto 0);
      link_status_o: out link_status_t;
      
      cmd_o  : out framed_req;
      cmd_i  : in  framed_ack;
      rsp_i  : in  framed_req;
      rsp_o  : out framed_ack
      );
  end component;

  -- RGMII in-band interframe status
  -- This is not supported by all Phys.
  component link_monitor_inband_status is
    generic(
      debounce_count_c : integer := 4
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      link_status_o: out link_status_t;

      rx_clock_i : in std_ulogic;
      rx_flit_i : in mii_flit_t
      );
  end component;

  function phy_supports(t: phy_type_t; speed: link_speed_t) return boolean;
  function phy_supports(t: phy_type_t; duplex: link_duplex_t) return boolean;
  function rgmii_ibs_decode(rxd: std_ulogic_vector(3 downto 0)) return link_status_t;
  function rgmii_ibs_encode(st: link_status_t) return std_ulogic_vector;

end package link_monitor;

package body link_monitor is

  function phy_supports(t: phy_type_t; speed: link_speed_t) return boolean
  is
  begin
    case t is
      when PHY_DP83xxx | PHY_RTL8211F => return true;
      when PHY_LAN8710 => return speed /= LINK_SPEED_1000;
    end case;
  end function;

  function phy_supports(t: phy_type_t; duplex: link_duplex_t) return boolean
  is
  begin
    return true;
  end function;

  -- See RGMII-v2.0, Table 4, Inter-frame In-band status
  -- Only valid when rx_dv and rx_er are deasserted
  function rgmii_ibs_decode(rxd: std_ulogic_vector(3 downto 0)) return link_status_t
  is
    variable ret: link_status_t;
  begin
    ret.up := rxd(0) = '1';

    case rxd(2 downto 1) is
      when "00" => ret.speed := LINK_SPEED_10;
      when "01" => ret.speed := LINK_SPEED_100;
      when others => ret.speed := LINK_SPEED_1000;
    end case;

    case rxd(3) is
      when '1' => ret.duplex := LINK_DUPLEX_FULL;
      when others => ret.duplex := LINK_DUPLEX_HALF;
    end case;

    return ret;
  end function;

  -- See RGMII-v2.0, Table 4, Inter-frame In-band status
  -- Only valid when rx_dv and rx_er are deasserted
  function rgmii_ibs_encode(st: link_status_t) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(3 downto 0);
  begin
    ret(0) := to_logic(st.up);

    case st.speed is
      when LINK_SPEED_10 => ret(2 downto 1) := "00";
      when LINK_SPEED_100 => ret(2 downto 1) := "01";
      when others => ret(2 downto 1) := "10";
    end case;

    case st.duplex is
      when LINK_DUPLEX_FULL => ret(3) := '1';
      when others =>  ret(3) := '0';
    end case;

    return ret;
  end function;
    
end package body link_monitor;
