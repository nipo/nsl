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

  type mii_flit_t is record
    data   : std_ulogic_vector(7 downto 0);
    valid  : std_ulogic;
    error  : std_ulogic;
  end record;

  component mii_flit_from_committed is
    generic(
      ipg_c : natural := 96 -- bits
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      committed_i : in nsl_bnoc.committed.committed_req;
      committed_o : out nsl_bnoc.committed.committed_ack;

      flit_o : out mii_flit_t;
      ready_i : in std_ulogic
      );
  end component;
  
  component mii_flit_to_committed is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      flit_i : in mii_flit_t;
      valid_i : in std_ulogic;

      committed_o : out nsl_bnoc.committed.committed_req;
      committed_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  end component;

end package mii;
