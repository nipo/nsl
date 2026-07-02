library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding;
use nsl_line_coding.ibm_8b10b.all;

library work;
use work.flit.all;

package sgmii is

  subtype config_reg_t is std_ulogic_vector(15 downto 0);

  component sgmii_pcs_rx is
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      symbol_i    : in  nsl_line_coding.ibm_8b10b.data_t;

      flit_o         : out mii_flit_t;
      config_valid_o : out std_ulogic;
      config_o       : out config_reg_t;
      idle_match_o   : out std_ulogic
      );
  end component;

  component sgmii_pcs_tx is
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      flit_i      : in  mii_flit_t;

      symbol_o    : out nsl_line_coding.ibm_8b10b.data_t;

      send_config_i : in  std_ulogic;
      config_i      : in  config_reg_t;
      link_up_i     : in  std_ulogic
      );
  end component;

  component sgmii_autoneg is
    generic(
      link_timer_cycles_c : natural := 1250000
      );
    port(
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      config_i    : in  config_reg_t;
      restart_i   : in  std_ulogic := '0';

      rx_config_valid_i : in  std_ulogic;
      rx_config_i       : in  config_reg_t;
      rx_idle_i         : in  std_ulogic;

      send_config_o    : out std_ulogic;
      tx_config_o      : out config_reg_t;
      link_up_o        : out std_ulogic;
      partner_config_o : out config_reg_t
      );
  end component;

end package sgmii;
