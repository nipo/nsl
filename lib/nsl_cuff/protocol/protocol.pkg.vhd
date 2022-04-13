library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding, nsl_data;
use nsl_line_coding.ibm_8b10b.all;

-- ======================================
-- Communication utility for fpga to fpga
-- ======================================
--
-- CUFF comes with various levels of protocol:
--
-- * Lane-level, where a lane is either training or ready to send
--   bytestream,
--
-- * Link-level, where one or many lanes (up to 16) are trunked together.
--   Inter-lane word alignment is trained and enforced.
--
-- * Network-level, where a bidirectional link is used for
--   transporting one bidirectional data stream with reliability
--   assertion and error detection.
--
-- Low-level Protocol design
-- =========================
--
-- Protocol uses IBM 8b10b encoding. It uses control words for
-- internal management (no data, frame boundary, synchronization, link
-- training).  It can use 1 to 16 physical lanes.  Transport may
-- either use explicit clock or use clock recovery.  Physical
-- transceiver is decoupled from the lane/link layer.
--
-- There is a transport synchronization phase that allows to
-- synchronize bit stream on each lane, and all the lanes
-- together. Moreover, transport synchronization phase asserts
-- integrity of core instantiation parameters.
--
-- Once ready, a N-lane link-layer offers an unidirectional
-- synchronous pipe for a N-byte wide stream. Byte data may be, for
-- each lane, replaced by idle or frame boundary marker.
--
-- Protocol states
-- ---------------
--
-- - Lane bit synchronization
--
--   Data transport is not ready. Transmitter sends continuous
--   synchronization frames. Each lane receiver uses synchronization frames for
--   word-alignment and input delay calibration.
--
-- - Inter-Lane synchronization
--
--   Data transport is not ready. Transmitter sends continuous
--   synchronization frames. Link-layer aligns a +/- 1 word delay
--   across the lanes. It also check the instantiation
--   parameters. Only a bus with the right properties will be accepted
--   by receiver.
--
-- - Ready
--
--   Data transport is not active yet. Transmitter sends continuous
--   synchronization frames with information that it is ready to start
--   reception of data.
--
-- - Running
--
--   Link is ready for data transport. Link is filled with data frames
--   or data-related control words.
--
-- Synchronization frames
-- ======================
--
-- Synchronization frames are sent during link lane bit synchronization, inter-lane
-- synchronization and ready states.
--
-- Synchronization frames allow receiver to do bit synchronization
-- (bit slip recovery) and word syncrhonization among physical lanes.
--
-- Synchronization frames are made of 5 x N words (N is number of
-- physical lanes). Depending on whether we are on main lane or a
-- secondary lane, sync frame is not exactly the same.
--
-- =========== =============== ====================== =======
-- Word index  Word name       Data                   Use
-- =========== =============== ====================== =======
-- 0           Sync SOF        K.28.2, K.28.0, K.29.7 Frame sync, inter-lane sync
-- 1           Instance params Param byte or K.30.7   Instance check, Inter-lane sync
-- 2           Lane ID         Lane no/Frame CTR      Integrity check
-- 3           Bit sync        D.21.5                 Bit sync
-- 4           Sync EOF        K.28.7                 Bit sync, inter-lane sync
--
-- Sync SOF
-- --------
--
-- - On main lane (index 0): K.28.2 in synchronization states, K28.0 when ready.
-- - On secondary lanes: K.29.7.
--
-- Instance params
-- ---------------
--
-- - On main lane, it contains two 4-bit fields, MSB is data frame MTU
--   as log2 (e.g. 0b0110 = 64 bytes). LSBs contain the count of data
--   lanes, minus one (e.g. 0b0001 = 2 lanes).
-- - On secondary lanes: K.30.7 (fill symbol).
--
-- Lane ID
-- -------
--
-- Contain the lane number in 4 MSBs, and an incremental counter (+1
-- for each new sync frame) in 4 LSBs. Counter is identical in all
-- lanes of the same sync frame.
--
-- Bit sync
-- --------
--
-- This is a fixed data word: D.21.5.  By design, it has maximum
-- transition count (encoded as 10b 0x2aa or 0x155). It helps
-- calibrating input delays.
--
-- Sync EOF
-- --------
--
-- Constant. Useful for properties below.
--
-- Properties
-- ----------
--
-- When a receiver receives a sync frame, it has to:
--
-- - Recover clock (if not transported on its own),
-- - Recover bit alignment (do bit slipping in deserializer until
--   words have a meaning),
-- - Recover inter-lane synchronization.
--
-- For bit alignment, sync frame contains K.28.7, the singular comma,
-- which has maximal disparity and run length.  It allows unambiguous
-- bit alignment checking and word alignment recovery.
--
-- For fine receiver synchronization, sync frame also explicitly
-- contains D.21.5 that yields a 1010101010 pattern.
--
-- For inter-lane alignment, when Sync SOF (either K.28.2 or K.28.0)
-- appears on main lane, there should be matching Sync SOF words on
-- secondary channels: K.29.7. If a secondary channel is late,
-- instance params word slot will appear, it will be K.30.7.  If a
-- secondary channel is early, previous Sync EOF will appear, it will
-- be K.28.7.  In terms of encoding:
-- - Late:    K.28.7  -> 111 11000
-- - On time: K.29.7  -> 111 11001
-- - Early:   K.30.7  -> 111 11010
--
-- Example Sync frame for a 1-lane transport
-- -----------------------------------------
--
-- Assuming MTU of 64 bytes:
--
-- - Training: K.28.2, 0x60, 0x0t, 0xb5, K.28.7 (with t incrementing)
-- - Synced: K.28.0, 0x60, 0x0t, 0xb5, K.28.7 (with t incrementing)
--
-- Example Sync frame for a 2-lane transport
-- -----------------------------------------
--
-- Assuming MTU of 64 bytes:
--
-- - Training:
--   - lane 0: K.28.2,   0x61, 0x0t, 0xb5, K.28.7 (with t incrementing)
--   - lane 1: K.29.7  K.30.7, 0x1t, 0xb5, K.28.7 (with t equal to lane 0)
-- - Ready:
--   - lane 0: K.28.0,   0x61, 0x0t, 0xb5, K.28.7 (with t incrementing)
--   - lane 1: K.29.7  K.30.7, 0x1t, 0xb5, K.28.7 (with t equal to lane 0)
--
-- Link layer data
-- ===============
--
-- Link-layer data is, for each lane simultaneously, one of:
-- 
-- - data byte,
-- - an idle symbol: K.28.1,
-- - a control symbol: K.28.[3,4,6], K[30,23,27].7.
--
-- Network layer
-- =============
--
-- Network layer may use the data pipe as it wants.
--
package protocol is

  -- Sync frame management
  -- Sync frame SOF
  constant CUFF_SYNC_SOF_MAIN  : data_t := K28_2;
  -- Sync frame SOF when ready
  constant CUFF_SYNC_SOF_READY : data_t := K28_0;
  -- Sync frame SOF for secondary channels
  constant CUFF_SYNC_SOF_SEC   : data_t := K29_7;
  -- Sync frame fill for secondary channels
  constant CUFF_SYNC_FILL      : data_t := K30_7;
  -- Sync frame EOF
  -- Singular comma, not repeated
  constant CUFF_SYNC_EOF       : data_t := K28_7;
  constant CUFF_SYNC_BITSYNC   : data_t := data(21,5);

  -- Data frame management
  -- Idle word
  -- Comma
  constant CUFF_DATA_IDLE   : data_t := K28_1;
  constant CUFF_DATA_CTRL0  : data_t := K28_3;
  constant CUFF_DATA_CTRL1  : data_t := K28_4;
  constant CUFF_DATA_CTRL2  : data_t := K28_6;
  constant CUFF_DATA_CTRL3  : data_t := K30_7;
  constant CUFF_DATA_CTRL4  : data_t := K23_7;
  constant CUFF_DATA_CTRL5  : data_t := K27_7;

  type cuff_data_control_t is (
    CUFF_DATA,
    CUFF_IDLE,
    -- Protocol mapping for these additional control words is left for
    -- the network layer
    CUFF_CTRL0,
    CUFF_CTRL1,
    CUFF_CTRL2,
    CUFF_CTRL3,
    CUFF_CTRL4,
    CUFF_CTRL5
    );
  
  type cuff_data_t is
  record
    data: nsl_data.bytestream.byte;
    control: cuff_data_control_t;
  end record;

  alias cuff_code_word_t is code_word_t;
  
  type cuff_data_vector is array (natural range <>) of cuff_data_t;
  type cuff_code_vector is array (natural range <>) of cuff_code_word_t;

  function cuff_data_encode(d: cuff_data_t) return nsl_line_coding.ibm_8b10b.data_t;
  function cuff_data_decode(d: nsl_line_coding.ibm_8b10b.data_t) return cuff_data_t;

  constant cuff_data_idle_c: cuff_data_t := (control => CUFF_IDLE,
                                             data => "--------");
  
end package protocol;

package body protocol is

  function cuff_data_encode(d: cuff_data_t) return nsl_line_coding.ibm_8b10b.data_t
  is
  begin
    case d.control is
      when CUFF_DATA  => return nsl_line_coding.ibm_8b10b.data(d.data);
      when CUFF_IDLE  => return CUFF_DATA_IDLE;
      when CUFF_CTRL0 => return CUFF_DATA_CTRL0;
      when CUFF_CTRL1 => return CUFF_DATA_CTRL1;
      when CUFF_CTRL2 => return CUFF_DATA_CTRL2;
      when CUFF_CTRL3 => return CUFF_DATA_CTRL3;
      when CUFF_CTRL4 => return CUFF_DATA_CTRL4;
      when CUFF_CTRL5 => return CUFF_DATA_CTRL5;
    end case;
  end function;
        
  function cuff_data_decode(d: nsl_line_coding.ibm_8b10b.data_t) return cuff_data_t
  is
  begin
    if d.control = '0' then
      return cuff_data_t'(data => d.data, control => CUFF_DATA);
    end if;
    if d = CUFF_DATA_CTRL0 then return cuff_data_t'(data => "--------", control => CUFF_CTRL0); end if;
    if d = CUFF_DATA_CTRL1 then return cuff_data_t'(data => "--------", control => CUFF_CTRL1); end if;
    if d = CUFF_DATA_CTRL2 then return cuff_data_t'(data => "--------", control => CUFF_CTRL2); end if;
    if d = CUFF_DATA_CTRL3 then return cuff_data_t'(data => "--------", control => CUFF_CTRL3); end if;
    if d = CUFF_DATA_CTRL4 then return cuff_data_t'(data => "--------", control => CUFF_CTRL4); end if;
    if d = CUFF_DATA_CTRL5 then return cuff_data_t'(data => "--------", control => CUFF_CTRL5); end if;
    return cuff_data_t'(data => "--------", control => CUFF_IDLE);
  end function;

end package body protocol;
