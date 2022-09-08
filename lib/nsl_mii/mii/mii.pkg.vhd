library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc;
use nsl_data.bytestream.all;

package mii is
  -- IEEE-802.3 MAC-centric naming of signals

  -- In MII mode, Phy creates two clocks (one for RX, one for TX).
  --
  -- TX signals travel from MAC to Phy, Clock is driven by Phy.
  -- i.e. signal and clock go in different directions.
  -- MAC outputs TX signals between 0ns and 25ns after rising edge
  -- of clock, as received by the MAC (so Phy will receive changes
  -- after a round-trip of clock + 0-25ns).
  -- MAC updates signals ASAP on received rising edge to be in time
  -- for next rising edge at Phy, Phy samples on rising edge.
  --
  -- RX signals travel from Phy to MAC, clock is driven by the Phy.
  -- i.e. signal and clock go in the same direction.
  -- Signals have 10ns/10ns setup/hold time requirements.
  -- With 25MHz clock, we have 20ns half cycle -> Phy can update on
  -- falling edge.
  
  -- MII Base signaling
  type mii_rx_p2m is
  record
    clk : std_ulogic;
    d   : std_ulogic_vector(3 downto 0);
    dv  : std_ulogic;
    er  : std_ulogic;
  end record;

  type mii_status_p2m is
  record
    crs    : std_ulogic;
    col    : std_ulogic;
  end record;

  type mii_tx_p2m is
  record
    clk : std_ulogic;
  end record;

  type mii_tx_m2p is
  record
    d   : std_ulogic_vector(3 downto 0);
    en  : std_ulogic;
    er  : std_ulogic;
  end record;

  type mii_m2p is
  record
    tx : mii_tx_m2p;
  end record;

  type mii_p2m is
  record
    status : mii_status_p2m;
    rx : mii_rx_p2m;
    tx : mii_tx_p2m;
  end record;

  type mii_io is
  record
    p2m: mii_p2m;
    m2p: mii_m2p;
  end record;
  
  component mii_driver is
    generic(
      -- Either "resync" or "oversampled"
      implementation_c: string := "resync";
      ipg_c : natural := 96 --bits
      );
    port(
      reset_n_i : in std_ulogic;
      -- MAC clock, equal or faster than actual RX and TX clocks for "resync",
      -- at least 2x TX/RX clock for "oversampled"
      clock_i : in std_ulogic;

      -- Synchronous to clock_i
      rx_sfd_o: out std_ulogic;
      tx_sfd_o: out std_ulogic;

      mii_o : out mii_m2p;
      mii_i : in  mii_p2m;

      rx_o : out nsl_bnoc.committed.committed_req;
      rx_i : in nsl_bnoc.committed.committed_ack;

      tx_i : in nsl_bnoc.committed.committed_req;
      tx_o : out nsl_bnoc.committed.committed_ack
      );
  end component;

  -- MII driver that resynchronizes all signals internally using fifos.
  -- Instantiates clock buffers as needed
  component mii_driver_resync is
    generic(
      ipg_c : natural := 96 --bits
      );
    port(
      reset_n_i : in std_ulogic;
      -- MAC clock, equal or faster than actual RX and TX clocks.
      clock_i : in std_ulogic;

      -- In clock_i domain
      rx_sfd_o: out std_ulogic;
      tx_sfd_o: out std_ulogic;

      mii_o : out mii_m2p;
      mii_i : in  mii_p2m;

      -- Syncronized to clock_i
      rx_o : out nsl_bnoc.committed.committed_req;
      rx_i : in nsl_bnoc.committed.committed_ack;

      tx_i : in nsl_bnoc.committed.committed_req;
      tx_o : out nsl_bnoc.committed.committed_ack
      );
  end component;

  -- MII driver with oversampled TX/RX clock
  component mii_driver_oversampled is
    generic(
      ipg_c : natural := 96 --bits
      );
    port(
      reset_n_i : in std_ulogic;
      -- MAC clock, at least 2x MII clock
      clock_i : in std_ulogic;

      -- In clock_i domain
      rx_sfd_o: out std_ulogic;
      tx_sfd_o: out std_ulogic;

      mii_o : out mii_m2p;
      mii_i : in  mii_p2m;

      rx_o : out nsl_bnoc.committed.committed_req;
      rx_i : in nsl_bnoc.committed.committed_ack;

      tx_i : in nsl_bnoc.committed.committed_req;
      tx_o : out nsl_bnoc.committed.committed_ack
      );
  end component;

end package mii;
