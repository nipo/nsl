library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc, work;
use nsl_data.bytestream.all;
use work.link.all;

package rmii is
  
  -- RMII Base signaling, reference clock is external
  -- RMII from Phy to Mac
  type rmii_p2m is record
    rx_d   : std_ulogic_vector(1 downto 0);
    rx_er  : std_ulogic;
    crs_dv : std_ulogic;
  end record;

  -- RMII from Mac to Phy
  type rmii_m2p is record
    tx_d   : std_ulogic_vector(1 downto 0);
    tx_en  : std_ulogic;
  end record;

  -- RMII signal group
  type rmii_io is
  record
    ref_clk : std_ulogic;
    p2m : rmii_p2m;
    m2p : rmii_m2p;
  end record;
  
  component rmii_driver_resync is
    generic(
      ipg_c : natural := 96 --bits
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      rmii_ref_clock_i: in std_ulogic;
      rmii_o : out rmii_m2p;
      rmii_i : in  rmii_p2m;

      link_speed_i: in link_speed_t := LINK_SPEED_100;

      -- In clock_i domain
      tx_sfd_o : out std_ulogic;
      rx_sfd_o : out std_ulogic;
      
      rx_o : out nsl_bnoc.committed.committed_req;
      rx_i : in nsl_bnoc.committed.committed_ack;

      tx_i : in nsl_bnoc.committed.committed_req;
      tx_o : out nsl_bnoc.committed.committed_ack
      );
  end component;

end package rmii;
