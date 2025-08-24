library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, work;
use work.flit.all;
use work.link.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;

package rgmii is

  -- RGMII is a transport for Layer 1.  Frames in and out of RGMII
  -- transceiver contain the whole ethernet frame, including FCS.
  -- Payload may be padded. Padding is carried over.  There is no
  -- minimal size for frame TX, it is up to transmitter to abide
  -- minimal size constraints.
  --
  -- Layer 1 <-> layer 2 frame components:
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status
  --   [0]   Frame complete
  --   [7:1] Reserved

  -- RGMII Base signaling, reference clock is external
  -- RGMII from Phy to Mac
  type rgmii_io_group_t is record
    d   : std_ulogic_vector(3 downto 0);
    c   : std_ulogic;
    ctl : std_ulogic;
  end record;

  -- RGMII signal group
  type rgmii_io is
  record
    p2m : rgmii_io_group_t;
    m2p : rgmii_io_group_t;
  end record;

  type rgmii_sdr_io_t is record
    -- data[3:0] + ctl(0), on wire first
    -- data[7:4] + ctl(1), on wire last
    data   : std_ulogic_vector(7 downto 0);
    dv, er : std_ulogic;
  end record;
  
  -- RGMII driver. Implements 10/100/1000 transparently. Always feed a
  -- 125 MHz clock to TX clock.
  component rgmii_driver is
    generic(
      rx_clock_delay_ps_c: natural := 0;
      tx_clock_delay_ps_c: natural := 0;
      -- In bit time
      ipg_c : natural := 96
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      rgmii_o : out rgmii_io_group_t;
      rgmii_i : in  rgmii_io_group_t;
      
      mode_i : in link_speed_t;

      -- SFD detection, synchronous to clock_i
      rx_sfd_o: out std_ulogic;
      tx_sfd_o: out std_ulogic;

      -- RX path copy for in-band status, clock probing, etc.
      -- No datapath should be taken from this
      -- Clock is buffered already
      rx_clock_o : out std_ulogic;
      rx_flit_o : out mii_flit_t;
      
      rx_o : out committed_req;
      rx_i : in committed_ack;

      tx_i : in committed_req;
      tx_o : out committed_ack
      );
  end component;

  component rgmii_tx_driver is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mode_i : in link_speed_t;
      flit_i : in rgmii_sdr_io_t;
      ready_o : out std_ulogic;
      sfd_o: out std_ulogic;

      rgmii_o : out rgmii_io_group_t
      );
  end component;

  component rgmii_rx_driver is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Buffered RX clock, for measurement, if any
      rx_clock_o : out std_ulogic;
      -- SFD detection, synchronous to rx_clock_o
      sfd_o: out std_ulogic;

      mode_i : in link_speed_t;
      rgmii_i : in  rgmii_io_group_t;

      flit_o : out rgmii_sdr_io_t;
      valid_o : out std_ulogic
      );
  end component;

  component gmii_to_rgmii is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      gmii_clk_i : in std_ulogic;
      gmii_i : in work.gmii.gmii_io_group_t;

      rgmii_o : out rgmii_io_group_t
      );
  end component;

  component rgmii_to_gmii is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      rgmii_i : in  rgmii_io_group_t;

      gmii_clk_o : out std_ulogic;
      gmii_o : out  work.gmii.gmii_io_group_t
      );
  end component;

end package rgmii;
