library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_sdio;

-- Sipeed PMOD-TF-Card: a microSD socket wired straight to the eight
-- PMOD data pins, with nothing in between but pull-ups and a card
-- detect switch.
--
--   pin 1: DAT3    pin 7: DAT1
--   pin 2: CMD     pin 8: DAT2
--   pin 3: DAT0    pin 9: card detect, low while a card is in
--   pin 4: CLK     pin 10: write protect, tied high
--
-- The board holds the command and data lines with 470 kOhm, which
-- defines them while nothing drives them but is far weaker than the
-- 10 to 100 kOhm a bus asks for.  Board constraints must therefore
-- enable the pull-ups of the six command and data pads.
--
-- The socket is fed 3.3 V, so the bus cannot be switched to the 1.8 V
-- signalling the faster modes need: high speed, 50 MHz and 25 MB/s
-- over four lines, is as far as this board goes.
package pmod_tf_card is

  -- The pads of the socket and the buffers they need, plus the one
  -- thing that is not a pad: the settling of the socket's contact,
  -- whose time is a property of this board and of nothing above it.
  -- A socket reached through a port expander gets that for free, one
  -- reached through pins does not.
  --
  -- Data lines above the four a socket has are not wired: what a host
  -- drives there goes nowhere, and they read as ones.
  component pmod_tf_card_pads is
    generic(
      clock_i_hz_c: natural;
      -- Time the contact has to hold still.  Pushing a card in wipes
      -- it for a while.
      card_stable_us_c: natural := 100000
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      pmod_io: inout nsl_digilent.pmod.pmod_double_t;

      sdio_i: in nsl_sdio.sdio.sdio_master_o;
      sdio_o: out nsl_sdio.sdio.sdio_master_i;

      -- Set while a card sits in the socket, settled and in this
      -- clock's domain.
      --
      -- Nothing on the bus may be gated on this.  Plenty of sockets
      -- have no such contact, plenty of boards leave it unwired, and
      -- a card answers or it does not whatever a switch says.  It is
      -- there to tell a user, and to know when to look again.
      card_present_o: out std_ulogic
      );
  end component;

end package pmod_tf_card;
