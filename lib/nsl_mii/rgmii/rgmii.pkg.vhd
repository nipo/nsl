library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

package rgmii is

  type rgmii_signal is
  record
    d   : std_ulogic_vector(3 downto 0);
    ctl : std_ulogic;
    c   : std_ulogic;
  end record;

  type rgmii_pipe is
  record
    data  : std_ulogic_vector(7 downto 0);
    valid : std_ulogic;
    error : std_ulogic;
    clock : std_ulogic;
  end record;

  component rgmii_signal_driver is
    port(
      phy_o : out rgmii_signal;
      phy_i : in  rgmii_signal;
      mac_o : out rgmii_pipe;
      mac_i : in  rgmii_pipe
      );
  end component;

  component rgmii_from_framed is
    generic(
      ipg_c : natural := 96/8
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      framed_i : in nsl_bnoc.framed.framed_req;
      framed_o : out nsl_bnoc.framed.framed_ack;

      rgmii_o : out rgmii_pipe
      );
  end component;

  component rgmii_to_framed is
    port(
      clock_o : out std_ulogic;
      reset_n_i : in std_ulogic;

      valid_o : out std_ulogic;
      framed_o : out nsl_bnoc.framed.framed_req;
      framed_i : in nsl_bnoc.framed.framed_ack;

      rgmii_i : in rgmii_pipe
      );
  end component;

end package rgmii;
