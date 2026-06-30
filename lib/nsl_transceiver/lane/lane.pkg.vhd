library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Signal interface between a transceiver group block and a protocol
-- adapter, for a single lane. The lane is exposed as two
-- independent unidirectional buses (TX and RX) plus a shared PMA
-- reset, so an application that owns TX and RX with separate
-- adapters (e.g. a daisy-chain ring topology) can wire them
-- independently. Records carry the worst-case set of signals;
-- a per-lane configuration object declares which subset is
-- meaningful. Bits not used by the configuration are expected to
-- carry '-' so synthesis can strip them.
package lane is

  -- Worst-case parallel datapath width. 32 bytes accommodates
  -- 256-bit user interfaces seen on current high-speed transceivers.
  constant max_data_byte_count_c : natural := 32;

  -- Auxiliary bits accompanying each data byte. Bit assignment is
  -- profile-dependent. Typical 8b10b profile: bit 0 = K, bit 1 =
  -- decode error, bit 2 = disparity error, bit 3 = current running
  -- disparity. 64b/66b profile uses a few bits per block instead.
  -- Sized to a byte to keep the carrier array regular.
  subtype aux_t is std_ulogic_vector(7 downto 0);
  type aux_string is array (natural range <>) of aux_t;
  subtype data_aux_t is aux_string(0 to max_data_byte_count_c-1);

  -- Vendor-opaque per-lane control and status carriers. Bit
  -- assignment is not portable between vendors; the protocol
  -- adapter and the group entity for a given target agree on the
  -- layout.
  constant max_control_width_c : natural := 64;
  constant max_status_width_c : natural := 32;
  subtype control_t is std_ulogic_vector(max_control_width_c-1 downto 0);
  subtype status_t is std_ulogic_vector(max_status_width_c-1 downto 0);

  type encoding_t is (
    ENCODING_RAW,
    ENCODING_8B10B,
    ENCODING_64B66B,
    ENCODING_128B130B
    );

  type loopback_mode_t is (
    LOOPBACK_NONE,
    LOOPBACK_NEAR_END_PMA,
    LOOPBACK_NEAR_END_PCS,
    LOOPBACK_FAR_END_PMA,
    LOOPBACK_FAR_END_PCS
    );

  -- Worst-case alignment / framing pattern width.
  constant max_pattern_byte_count_c : natural := 4;
  subtype pattern_t is byte_string(0 to max_pattern_byte_count_c-1);

  -- Word alignment and rate-matching parameters. All vectors are
  -- sized to the worst case; the byte-count fields declare how many
  -- bytes of each pattern are meaningful.
  type sync_t is
  record
    -- Symbol that triggers word alignment on the RX side. The mask
    -- declares which bits of the value are care bits.
    comma_value : pattern_t;
    comma_mask : pattern_t;
    comma_byte_count : natural range 0 to max_pattern_byte_count_c;
    -- True when the comma the receiver should look for is the
    -- bitwise negation of comma_value. Used on transceivers lacking
    -- runtime RX polarity invert when the upstream device sends
    -- with reversed differential polarity.
    comma_negated : boolean;
    -- Rate-matching sequence the receiver may add/remove from the
    -- stream as elastic buffer fill demands.
    clock_correction_pattern : pattern_t;
    clock_correction_byte_count : natural range 0 to max_pattern_byte_count_c;
    -- Pattern emitted on TX when the upstream adapter does not have
    -- a word to send (i.e. tx.m.valid = '0').
    idle_pattern : pattern_t;
    idle_byte_count : natural range 0 to max_pattern_byte_count_c;
  end record;

  constant null_sync_c : sync_t := (
    comma_value => (others => (others => '-')),
    comma_mask => (others => (others => '0')),
    comma_byte_count => 0,
    comma_negated => false,
    clock_correction_pattern => (others => (others => '-')),
    clock_correction_byte_count => 0,
    idle_pattern => (others => (others => '-')),
    idle_byte_count => 0
    );

  -- Analog/PMA tuning. Values are vendor-mapped by the group entity
  -- (e.g. quantised to the nearest available setting); zero asks
  -- for the vendor's sensible default.
  type analog_t is
  record
    tx_swing_mv : natural;
    tx_preemphasis_db : natural;
    rx_equalization_db : natural;
    rx_termination_milliohm : natural;
  end record;

  constant default_analog_c : analog_t := (
    tx_swing_mv => 0,
    tx_preemphasis_db => 0,
    rx_equalization_db => 0,
    rx_termination_milliohm => 0
    );

  -- Per-lane configuration. Describes the contract between the
  -- protocol adapter and the group entity: parallel data width,
  -- encoding, alignment, line rate, PLL/ref-clock routing, analog
  -- tuning. How a given vendor macroblock fulfils this contract is
  -- internal to the group entity.
  type config_t is
  record
    enabled : boolean;
    data_byte_count : natural range 0 to max_data_byte_count_c;
    encoding : encoding_t;
    line_rate_mbps : natural;
    pll_index : natural;
    ref_clock_index : natural;
    user_clock_group_index : natural;
    polarity_invert_tx : boolean;
    polarity_invert_rx : boolean;
    loopback : loopback_mode_t;
    sync : sync_t;
    analog : analog_t;
  end record;

  type config_vector is array (natural range <>) of config_t;

  function config(
    data_byte_count : natural;
    encoding : encoding_t := ENCODING_RAW;
    line_rate_mbps : natural := 0;
    pll_index : natural := 0;
    ref_clock_index : natural := 0;
    user_clock_group_index : natural := 0;
    polarity_invert_tx : boolean := false;
    polarity_invert_rx : boolean := false;
    loopback : loopback_mode_t := LOOPBACK_NONE;
    sync : sync_t := null_sync_c;
    analog : analog_t := default_analog_c
    ) return config_t;

  constant disabled_lane_c : config_t := (
    enabled => false,
    data_byte_count => 0,
    encoding => ENCODING_RAW,
    line_rate_mbps => 0,
    pll_index => 0,
    ref_clock_index => 0,
    user_clock_group_index => 0,
    polarity_invert_tx => false,
    polarity_invert_rx => false,
    loopback => LOOPBACK_NONE,
    sync => null_sync_c,
    analog => default_analog_c
    );

  -- TX path: signals driven by the adapter into the transceiver.
  -- The vendor backend may use only a subset of these fields,
  -- depending on what the underlying primitive exposes; surplus
  -- bits and signals stay at '-' / '0' and are pruned by synthesis.
  --
  -- ``control`` and ``control_h`` are paired opaque sideband vectors:
  -- some vendor primitives expose two independent runtime-control
  -- inputs per lane (for example, a "low-speed" and "high-speed"
  -- variant). Adapters that only need one populate ``control``.
  --
  -- ``c2i_clock`` is an adapter-driven per-lane fabric clock used
  -- by encodings where the protocol IP owns the lane's interface
  -- clock (some implementations of 8b/10b at moderate line rates).
  -- Adapters that don't need it leave it at '0'.
  type tx_master_t is
  record
    data : byte_string(0 to max_data_byte_count_c-1);
    aux : data_aux_t;
    valid : std_ulogic;
    pcs_reset_n : std_ulogic;
    control : control_t;
    control_h : control_t;
    c2i_clock : std_ulogic;
  end record;

  -- TX path: signals driven by the transceiver back to the adapter.
  type tx_slave_t is
  record
    ready : std_ulogic;
    pll_lock : std_ulogic;
    status : status_t;
  end record;

  type tx_t is
  record
    m : tx_master_t;
    s : tx_slave_t;
  end record;

  -- RX path: signals driven by the transceiver to the adapter.
  type rx_master_t is
  record
    data : byte_string(0 to max_data_byte_count_c-1);
    aux : data_aux_t;
    valid : std_ulogic;
    pma_lock : std_ulogic;
    pcs_aligned : std_ulogic;
    elec_idle : std_ulogic;
    status : status_t;
  end record;

  -- RX path: signals driven by the adapter back to the transceiver.
  type rx_slave_t is
  record
    ready : std_ulogic;
    pcs_reset_n : std_ulogic;
    align_trigger : std_ulogic;
    chbond_start : std_ulogic;
    control : control_t;
  end record;

  type rx_t is
  record
    m : rx_master_t;
    s : rx_slave_t;
  end record;

  -- Per-lane bundle. PMA reset is shared between TX and RX because
  -- a single primitive serves both directions; an application that
  -- owns TX and RX with two separate adapters is responsible for
  -- combining their reset requests externally.
  type io_t is
  record
    tx : tx_t;
    rx : rx_t;
    pma_reset_n : std_ulogic;
  end record;

  type tx_master_vector is array (natural range <>) of tx_master_t;
  type tx_slave_vector is array (natural range <>) of tx_slave_t;
  type tx_vector is array (natural range <>) of tx_t;
  type rx_master_vector is array (natural range <>) of rx_master_t;
  type rx_slave_vector is array (natural range <>) of rx_slave_t;
  type rx_vector is array (natural range <>) of rx_t;
  type io_vector is array (natural range <>) of io_t;

  constant null_tx_master_c : tx_master_t := (
    data => (others => (others => '-')),
    aux => (others => (others => '-')),
    valid => '-',
    pcs_reset_n => '-',
    control => (others => '-'),
    control_h => (others => '-'),
    c2i_clock => '-'
    );

  constant null_tx_slave_c : tx_slave_t := (
    ready => '-',
    pll_lock => '-',
    status => (others => '-')
    );

  constant null_rx_master_c : rx_master_t := (
    data => (others => (others => '-')),
    aux => (others => (others => '-')),
    valid => '-',
    pma_lock => '-',
    pcs_aligned => '-',
    elec_idle => '-',
    status => (others => '-')
    );

  constant null_rx_slave_c : rx_slave_t := (
    ready => '-',
    pcs_reset_n => '-',
    align_trigger => '-',
    chbond_start => '-',
    control => (others => '-')
    );

end package lane;

package body lane is

  function config(
    data_byte_count : natural;
    encoding : encoding_t := ENCODING_RAW;
    line_rate_mbps : natural := 0;
    pll_index : natural := 0;
    ref_clock_index : natural := 0;
    user_clock_group_index : natural := 0;
    polarity_invert_tx : boolean := false;
    polarity_invert_rx : boolean := false;
    loopback : loopback_mode_t := LOOPBACK_NONE;
    sync : sync_t := null_sync_c;
    analog : analog_t := default_analog_c
    ) return config_t
  is
    variable ret : config_t;
  begin
    ret := (
      enabled => true,
      data_byte_count => data_byte_count,
      encoding => encoding,
      line_rate_mbps => line_rate_mbps,
      pll_index => pll_index,
      ref_clock_index => ref_clock_index,
      user_clock_group_index => user_clock_group_index,
      polarity_invert_tx => polarity_invert_tx,
      polarity_invert_rx => polarity_invert_rx,
      loopback => loopback,
      sync => sync,
      analog => analog
      );
    return ret;
  end function;

end package body lane;
