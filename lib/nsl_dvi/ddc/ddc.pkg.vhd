library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_video;

-- DDC, the channel a source asks a sink what it is over.
--
-- It is I2C, with the sink answering as a memory at address 0x50
-- holding its EDID: a source writes one address byte, then reads as
-- many bytes as it wants.
package ddc is

  -- Address a sink answers its EDID at, fixed by the standard.
  constant edid_address_c: unsigned(7 downto 1) := "1010000";

  -- Answers a source's EDID reads with a block describing the modes
  -- on offer.
  --
  -- The block is built at elaboration from the modes themselves, so
  -- what is advertised here and what the rest of the design accepts
  -- come from one statement of the modes.  The first one is the
  -- preferred one, which is what a source picks unless told
  -- otherwise.
  --
  -- Reads past the end wrap round.  A source has no reason to go
  -- there: the block states how much there is to read.
  --
  -- Bus lines are open drain, so what comes out only ever pulls them
  -- down.  Hot plug detect is not here: it is one pin the design
  -- drives to say a sink is present at all, and it says nothing about
  -- DDC.
  component ddc_edid_slave is
    generic(
      modes_c : nsl_video.mode.mode_vector;
      manufacturer_c : string := "NSL";
      product_code_c : natural := 0;
      serial_c : natural := 0;
      week_c : natural := 0;
      year_c : natural := 2026;
      name_c : string := "";
      h_size_mm_c : natural := 0;
      v_size_mm_c : natural := 0;
      -- Offer an HDMI link rather than a DVI one.  This is what makes
      -- a source send data islands at all.
      hdmi_c : boolean := false;
      -- Channels of LPCM to ask for, zero for no audio.  Audio needs
      -- an HDMI link to travel on.
      audio_channels_c : natural := 0;
      address_c : unsigned(7 downto 1) := edid_address_c
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      i2c_i : in nsl_i2c.i2c.i2c_i;
      i2c_o : out nsl_i2c.i2c.i2c_o;

      -- A source is talking to us.
      selected_o : out std_ulogic
      );
  end component;

end package ddc;
