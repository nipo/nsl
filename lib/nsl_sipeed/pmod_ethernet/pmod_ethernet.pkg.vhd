library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_mii, nsl_amba;

-- Sipeed PMOD-Ethernet: a HanRun HR911130A magjack wired straight to
-- the eight PMOD data pins, with no Phy chip in between.  The four
-- RJ45 pairs land on facing PMOD pins, which is also how a PMOD
-- connector maps to the differential pairs of an FPGA:
--
--   pins 3/7: RJ45 3-6, the receive pair
--   pins 4/8: RJ45 1-2, the transmit pair
--   pins 1/5 and 2/6: RJ45 7-8 and 4-5, unused by 10BASE-T
--
-- Board constraints must give the receive pair a differential input
-- type with the on-die termination enabled, and put a weak pull-up on
-- one leg and a weak pull-down on the other leg of the unused pairs.
-- A winding is a DC short between its two legs, so those pulls settle
-- every pair near mid-supply, at the input threshold, through the
-- center taps the windings share.
package pmod_ethernet is

  -- Line-side signals, for instrumentation.  Probing the module from
  -- outside would mean bringing the pads back out, which defeats the
  -- point of the wrapper.
  type pmod_ethernet_probe_t is
  record
    -- Receive comparator output, asynchronous to any clock
    rx: std_ulogic;
    -- Transmit pair, only meaningful while tx_en is asserted
    tx_p: std_ulogic;
    tx_en: std_ulogic;
  end record;

  -- Medium Dependent Interface: the pads, the buffers they need, and
  -- nothing else.  Transmit is pseudo-differential and released while
  -- tx_en_i is low.
  component pmod_ethernet_mdi is
    generic(
      -- Whether to enable the on-die differential termination of the
      -- receive pair.  Clear it only if the pair is terminated on the
      -- board.
      rx_diff_term_c : boolean := true
      );
    port(
      pmod_io : inout nsl_digilent.pmod.pmod_double_t;

      tx_p_i : in std_ulogic;
      tx_n_i : in std_ulogic;
      tx_en_i : in std_ulogic;

      rx_o : out std_ulogic
      );
  end component;

  -- The above, driven by a fabric 10BASE-T MAU.  MAC-side interface
  -- is the mii flit interface, so the adapters of nsl_mii.flit give
  -- committed and axi4-stream framing.
  --
  -- clock_i must be a multiple of 20 MHz, and oversample the line by
  -- at least eight, so 100 MHz and above.
  component pmod_ethernet_10baset_mau is
    generic(
      clock_i_hz_c : natural;
      rx_diff_term_c : boolean := true;
      -- Off by default here: the receive comparator has no amplitude
      -- squelch, so this station's own transmission couples through
      -- the magnetics and reads as a permanent collision.  Deference
      -- still keeps the two directions apart, and an undetected
      -- collision costs one frame, which the upper layers resend.
      collision_detect_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pmod_io : inout nsl_digilent.pmod.pmod_double_t;

      flit_i : in nsl_mii.flit.mii_flit_t;
      ready_o : out std_ulogic;

      flit_o : out nsl_mii.flit.mii_flit_t;
      valid_o : out std_ulogic;

      link_up_o : out std_ulogic;
      polarity_inverted_o : out std_ulogic;
      crs_o : out std_ulogic;
      col_o : out std_ulogic;
      collision_o : out std_ulogic;
      late_collision_o : out std_ulogic;
      excessive_collision_o : out std_ulogic;

      probe_o : out pmod_ethernet_probe_t
      );
  end component;

  -- The above behind the flit to axi4-stream adapters.  Streams carry
  -- wire-level frames, FCS included, in nsl_mii.flit.axi4_flit_cfg
  -- configuration: one byte per beat, the user bit flagging a frame
  -- received in error.
  --
  -- The line has no flow control.  A receiver must accept beats as
  -- they come, and a transmitter must sustain one beat per eight line
  -- bit times once a frame starts, so both sides usually want a fifo
  -- between here and the stack.
  component pmod_ethernet_axi4_stream is
    generic(
      clock_i_hz_c : natural;
      rx_diff_term_c : boolean := true;
      collision_detect_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pmod_io : inout nsl_digilent.pmod.pmod_double_t;

      rx_o : out nsl_amba.axi4_stream.master_t;
      rx_i : in nsl_amba.axi4_stream.slave_t;

      tx_i : in nsl_amba.axi4_stream.master_t;
      tx_o : out nsl_amba.axi4_stream.slave_t;

      link_up_o : out std_ulogic;
      polarity_inverted_o : out std_ulogic;
      crs_o : out std_ulogic;
      col_o : out std_ulogic;
      collision_o : out std_ulogic;
      late_collision_o : out std_ulogic;
      excessive_collision_o : out std_ulogic;

      probe_o : out pmod_ethernet_probe_t
      );
  end component;

end package pmod_ethernet;
