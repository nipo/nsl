library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
  type mii_datapath is record
    d   : std_ulogic_vector(3 downto 0);
    dv  : std_ulogic;
    er  : std_ulogic;
  end record;

  -- Carrier sensing signals, Phy to MAC.
  -- CRS and COL have no timing requirements.
  type mii_status is record
    crs : std_ulogic;
    col : std_ulogic;
  end record;

  type rmii_datapath is record
    d  : std_ulogic_vector(1 downto 0);
    dv : std_ulogic;
  end record;

end package mii;
