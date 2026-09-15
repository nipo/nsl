library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

-- Digilent Pmod I2S2: two converters, one each way, each with an I2S
-- interface of its own.
--
-- The line out converter is on the top row of the double connector and
-- the line in converter on the bottom row, so the two halves are
-- independent and a design using one need not drive the other.  That
-- matters for the line in converter especially: a jumper decides
-- whether it makes its own word and bit clocks, and driving those at
-- one that does would fight it.
package pmod_i2s2 is

  -- Line out, taking the clocks it sends rather than making them.
  --
  -- A converter works out what rate it is being fed by counting master
  -- clocks in a word clock period, so the three clocks have to come
  -- from one place and keep step.  Where they come from is the
  -- caller's: a local divider serves a design that owns the rate, and
  -- a recovered tick serves one playing what arrived over a link.
  --
  -- The word carried is as wide as data_i, which is the slot rather
  -- than the sample: the converter takes the leading twenty four bits
  -- of each and ignores what follows, so a twenty four bit sample in
  -- the top of a thirty two bit slot is what a sixty four times word
  -- clock bit clock sends.
  component pmod_i2s2_line_out_driver is
    port(
      pmod_io: inout work.pmod.pmod_double_t;

      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mclk_i : in std_ulogic;
      sck_i : in std_ulogic;
      ws_i : in std_ulogic;

      ready_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_i : in unsigned
      );
  end component;

  -- Both converters, clocked off dividers of the local clock.
  --
  -- line_in_slave_c states the line in converter makes its own word
  -- and bit clocks, which is the jumper's master position: this reads
  -- them rather than driving them.
  component pmod_i2s2_driver is
    generic(
      line_in_slave_c: boolean := false
      );
    port(
      pmod_io: inout work.pmod.pmod_double_t;

      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      rx_mclk_i : in std_ulogic;
      rx_sck_div_m1_i : in unsigned;
      rx_valid_o : out std_ulogic;
      rx_channel_o : out std_ulogic;
      rx_data_o  : out unsigned;

      tx_mclk_i : in std_ulogic;
      tx_sck_div_m1_i : in unsigned;
      tx_ready_o : out std_ulogic;
      tx_channel_o : out std_ulogic;
      tx_data_i  : in unsigned
      );
  end component;

end package pmod_i2s2;
