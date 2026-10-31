library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding, nsl_io, nsl_bnoc;
use nsl_line_coding.ibm_8b10b.all;
use nsl_io.diff.all;

library work;
use work.flit.all;
use work.link.all;

package sgmii is

  subtype config_reg_t is std_ulogic_vector(15 downto 0);

  -- See IEEE 802.3 clause 37
  -- Full Duplex only, no pause, no next page
  constant config_1000BaseX_c : config_reg_t := "0000000000100000";
  -- 10ms
  constant link_timer_1000BaseX_c : natural := 1250000;

  -- See SGMII CISCO spec, table 1
  -- Auto-negotiation is done with the PHY
  -- Full Duplex, 1000BaseX mode
  constant config_sgmii_c : config_reg_t := "0001100000000001";
  
  -- SGMII spec says: "The link_timer inside the Auto-Negotiation has been 
  -- changed from 10 msec to 1.6 msec to ensure a prompt update of the link status."
  constant link_timer_sgmii_c : natural := 200000;

  -- Auto-negotiation configuration register advertised for the
  -- selected mode.
  function config_reg(sgmii_mode : boolean) return config_reg_t;

  -- Auto-negotiation link timer, in clock cycles. A zero override
  -- selects the duration the relevant specification mandates; any
  -- other value replaces it, which lets a simulation reach link-up
  -- without counting milliseconds of clock cycles.
  function link_timer_cycles(sgmii_mode : boolean;
                             override : natural) return natural;

  type sgmii_m2p_t is record
    symbol : nsl_line_coding.ibm_8b10b.data_t;
    tx_disparity    : std_ulogic;
    align_rst       : std_ulogic;
    valid_symbol    : std_ulogic;
  end record;

  type sgmii_p2m_t is record
    symbol : nsl_line_coding.ibm_8b10b.data_t;
    code_err        : std_ulogic;
    disparity_err   : std_ulogic;
    align_ready     : std_ulogic;
    clk_cor         : std_ulogic; -- 1 insert/skip, 0 none
  end record;

  type sgmii_m2p_vector is array (natural range <>) of sgmii_m2p_t;
  type sgmii_p2m_vector is array (natural range <>) of sgmii_p2m_t;

  component sgmii_driver is
    generic (
      sgmii_mode_c : boolean := false;
      link_timer_c : natural := 0
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      sgmii_o : out sgmii_m2p_t;
      sgmii_i : in  sgmii_p2m_t;

      link_speed_i : in  link_speed_t := LINK_SPEED_1000;
      link_up_o    : out std_ulogic;

      rx_o : out nsl_bnoc.committed.committed_req;
      rx_i : in  nsl_bnoc.committed.committed_ack;

      tx_i : in  nsl_bnoc.committed.committed_req;
      tx_o : out nsl_bnoc.committed.committed_ack
      );
  end component sgmii_driver;

  component sgmii_pcs_rx is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      symbol_i          : in  nsl_line_coding.ibm_8b10b.data_t;
      symbol_expected_o : out std_ulogic;

      clk_cor_i : in std_ulogic;

      flit_o         : out mii_flit_t;
      config_valid_o : out std_ulogic;
      config_o       : out config_reg_t;
      valid_o        : out std_ulogic;
      idle_match_o   : out std_ulogic
      );
  end component;

  component sgmii_pcs_tx is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      flit_i : in mii_flit_t;
      flit_ready_o : out std_ulogic;
    
      symbol_o : out nsl_line_coding.ibm_8b10b.data_t;
      -- Running disparity the encoder must use when encoding symbol_o
      -- ('1' = positive, '0' = negative). Same cycle as symbol_o. The
      -- backend must encode each symbol as if the RD before it were this
      -- value, so that the line follows this PCS's RD model exactly.
      disparity_o : out std_ulogic;      

      send_config_i : in std_ulogic;
      config_i      : in config_reg_t;
      link_up_i     : in std_ulogic
      );
  end component;

  component sgmii_autoneg is
    generic(
      link_timer_cycles_c : natural := 1250000
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      config_i  : in config_reg_t;
      restart_i : in std_ulogic := '0';

      rx_config_valid_i : in std_ulogic;
      rx_config_i       : in config_reg_t;
      rx_idle_i         : in std_ulogic;

      send_config_o    : out std_ulogic;
      tx_config_o      : out config_reg_t;
      link_up_o        : out std_ulogic;
      partner_config_o : out config_reg_t
      );
  end component;

  component sgmii_serdes_backend is
    port (
      reset_n_i  : in std_ulogic;
      clock125_i : in std_ulogic;
      clock625_i : in std_ulogic;

      sgmii_i : in  sgmii_m2p_t;
      sgmii_o : out sgmii_p2m_t;

      pair_diff_i : in  nsl_io.diff.diff_pair;
      pair_diff_o : out nsl_io.diff.diff_pair
      );
  end component;

end package sgmii;

package body sgmii is

  function config_reg(sgmii_mode : boolean) return config_reg_t
  is
  begin
    if sgmii_mode then
      return config_sgmii_c;
    else
      return config_1000BaseX_c;
    end if;
  end function;

  function link_timer_cycles(sgmii_mode : boolean;
                             override : natural) return natural
  is
  begin
    if override /= 0 then
      return override;
    elsif sgmii_mode then
      return link_timer_sgmii_c;
    else
      return link_timer_1000BaseX_c;
    end if;
  end function;

end package body sgmii;
