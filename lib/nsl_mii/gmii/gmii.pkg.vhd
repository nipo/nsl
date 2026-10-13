library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_smi;
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

  constant gmii_io_group_idle_c : gmii_io_group_t := (
    data => (others => '-'),
    en => '0',
    er => '0'
    );
  
  -- Pseudo GMII adapter, fixed at Gb traffic, dedicated to connection
  -- to Zynq-7 hard-IP. Behaves as a Phy to the GbE controller. Always
  -- feed a 125 MHz clock.
  --
  -- With indep_rx_clock_c, the path towards the controller (to_mac,
  -- RXD/RX_DV, CRS and the RX clock given to the controller) runs on
  -- rx_clock_i instead of clock_i, e.g. a clock recovered by an
  -- external Phy, with no relation to clock_i. rx_clock_i is ignored
  -- otherwise.
  component gmii_z7_phy is
    generic(
      -- In bit time
      ipg_c : natural := 96;
      indep_rx_clock_c : boolean := false;
      has_mdio_c : boolean := false;
      phy_addr_c : unsigned(4 downto 0) := (others => '0')
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;
      rx_clock_i : in std_ulogic := '0';

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
      to_mac_o : out committed_ack;

      smi_i : in nsl_smi.smi.smi_slave_i := (mdc => '1', mdio => '1');
      smi_o : out nsl_smi.smi.smi_slave_o;

      link_up_i : in std_ulogic := '0';
      mdio_resetn : out std_ulogic
      );
  end component;

end package gmii;
