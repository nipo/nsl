library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

package rgmii is

  -- RGMII is a transport for Layer 1.  Frames in and out of RGMII
  -- transceiver contain the whole ethernet frame, not including FCS,
  -- but with a status byte instead.  Payload may be padded. Padding
  -- is carried over.  There is no minimal size for frame TX, it is up
  -- to transmitter to abide minimal size constraints.
  --
  -- Layer 1 <-> layer 2 frame components:
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status
  --   [0]   CRC valid / Frame complete
  --   [7:1] Reserved

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
    generic(
      add_rx_delay_c: boolean := false;
      add_tx_delay_c: boolean := false
      );
    port(
      phy_o : out rgmii_signal;
      phy_i : in  rgmii_signal;
      mac_o : out rgmii_pipe;
      mac_i : in  rgmii_pipe
      );
  end component;

  component rgmii_from_committed is
    generic(
      ipg_c : natural := 96/8
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      committed_i : in nsl_bnoc.committed.committed_req;
      committed_o : out nsl_bnoc.committed.committed_ack;

      rgmii_o : out rgmii_pipe
      );
  end component;

  component rgmii_to_committed is
    port(
      clock_o : out std_ulogic;
      reset_n_i : in std_ulogic;

      committed_o : out nsl_bnoc.committed.committed_req;
      committed_i : in nsl_bnoc.committed.committed_ack;

      rgmii_i : in rgmii_pipe
      );
  end component;

end package rgmii;
