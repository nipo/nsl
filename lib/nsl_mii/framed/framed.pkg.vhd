library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;

package framed is

  component mii_to_framed is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mii_i : in nsl_mii.mii.mii_datapath;

      framed_o : out nsl_bnoc.framed.framed_req
      );
  end component;

  component mii_from_framed is
    generic(
      inter_frame : natural := 56
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mii_o : out nsl_mii.mii.mii_datapath;

      framed_i : in nsl_bnoc.framed.framed_req;
      framed_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

  component rmii_to_framed is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      rmii_i  : in nsl_mii.mii.rmii_datapath;

      framed_o : out nsl_bnoc.framed.framed_req
      );
  end component;

  component rmii_from_framed is
    generic(
      inter_frame : natural := 56
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      rmii_o  : out nsl_mii.mii.rmii_datapath;

      framed_i : in nsl_bnoc.framed.framed_req;
      framed_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

  component rmii_framed is
    generic(
      inter_frame : natural := 56;
      mtu : natural := 1024
      );
    port(
      reset_n_i    : in std_ulogic;

      rmii_clock_i  : in std_ulogic;
      rmii_o    : out nsl_mii.mii.rmii_datapath;
      rmii_i    : in  nsl_mii.mii.rmii_datapath;

      framed_clock_i: in std_ulogic;
      to_rmii_i    : in  nsl_bnoc.framed.framed_req;
      to_rmii_o    : out nsl_bnoc.framed.framed_ack;
      from_rmii_o  : out nsl_bnoc.framed.framed_req;
      from_rmii_i  : in  nsl_bnoc.framed.framed_ack
      );
  end component;
  
end package framed;
