library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;
use nsl_bnoc.committed.all;

package gmii is

  -- GMII is a transport for Layer 1.  Frames in and out of GMII
  -- transceiver contain the whole ethernet frame with a status byte.
  -- Payload may be padded. Padding is carried over.  There is no
  -- minimal size for frame TX, it is up to transmitter to abide
  -- minimal size constraints.
  --
  -- Layer 1 <-> layer 2 frame components:
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * FCS [*]
  -- * Status
  --   [0]   Frame complete (no error signaled by Phy)
  --   [7:1] Reserved

  type gmii_io_group_t is record
    data   : std_ulogic_vector(7 downto 0);
    -- en is called dv on RX path.
    en, er : std_ulogic;
  end record;
  
  -- Pseudo GMII adapter, fixed at Gb traffic, dedicated to connection
  -- to Zynq-7 hard-IP. Behaves as a Phy to the GbE controller. Always
  -- feed a 125 MHz clock.
  component gmii_z7_phy is
    generic(
      -- In bit time
      ipg_c : natural := 96
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      gmii_tx_i : in gmii_io_group_t;
      -- Zynq-7 GbE receives TX Clock from PL.
      gmii_tx_clk_o : out std_ulogic;
      gmii_col_o : out std_ulogic;

      gmii_crs_o : out std_ulogic;
      gmii_rx_clk_o : out std_logic;
      gmii_rx_o : out gmii_io_group_t;
      
      from_mac_o : out committed_req;
      from_mac_i : in committed_ack;

      to_mac_i : in committed_req;
      to_mac_o : out committed_ack
      );
  end component;

end package gmii;
