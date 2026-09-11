library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_line_coding, nsl_data;
use nsl_data.bytestream.all;

entity mau_10baset_tx is
  generic (
    clock_i_hz_c : natural;
    -- Whether receive activity during transmission is a collision.
    -- Clear it when the receive path cannot reject this station's own
    -- transmission, which would otherwise read as a permanent
    -- collision; deference still keeps the two directions apart.
    collision_detect_c : boolean := true;
    slow_timer_div_c : natural := 1
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    flit_i : in nsl_mii.flit.mii_flit_t;
    ready_o : out std_ulogic;

    -- Receive carrier, from the receiver of the same MAU.  Gates
    -- transmission start (deference) and flags collisions.
    carrier_i : in std_ulogic;

    transmitting_o : out std_ulogic;

    -- Strobes for one cycle on every detected collision.
    collision_o : out std_ulogic;
    -- Strobes for one cycle on a collision detected at or after the
    -- slot time.  Frame is abandoned.
    late_collision_o : out std_ulogic;
    -- Strobes for one cycle when a frame is abandoned after having
    -- collided on all of its attempts.
    excessive_collision_o : out std_ulogic;

    tx_p_o : out std_ulogic;
    tx_n_o : out std_ulogic;
    tx_en_o : out std_ulogic
    );
end entity;

architecture beh of mau_10baset_tx is

  constant signal_hz_c : natural := 10000000;
  constant bit_cycles_c : natural := clock_i_hz_c / signal_hz_c;
  -- Flit interface pacing.
  constant byte_cycles_c : natural := 8 * bit_cycles_c;
  -- TP_IDL start-of-idle marker, 300ns.
  constant tp_idl_cycles_c : natural := 3 * bit_cycles_c;
  -- Normal link pulse width, 100ns.
  constant nlp_cycles_c : natural := bit_cycles_c;
  -- Normal link pulse period, 16ms.
  constant nlp_period_cycles_c : natural
    := (clock_i_hz_c / 1000) * 16 / slow_timer_div_c;

  -- CSMA/CD constants.  These are protocol constants, they are never
  -- affected by slow_timer_div_c.
  --
  -- Slot time, 512 bit times.  A collision detected before this much
  -- of the frame has been transmitted may be retried, a collision
  -- detected later is a late collision.
  constant slot_bits_c : natural := 512;
  constant slot_cycles_c : natural := slot_bits_c * bit_cycles_c;
  -- Inter-frame gap, 96 bit times.
  constant ipg_bits_c : natural := 96;
  constant ipg_cycles_c : natural := ipg_bits_c * bit_cycles_c;
  -- Jam sequence, 32 bits of alternating data.
  constant jam_byte_c : byte := x"55";
  constant jam_bits_c : natural := 32;
  constant jam_bytes_c : natural := jam_bits_c / 8;
  -- Transmission attempts before a frame is abandoned.
  constant attempt_max_c : natural := 16;
  -- Backoff is drawn in [0, 2**min(attempts, 10) - 1].
  constant backoff_exp_max_c : natural := 10;
  constant backoff_max_c : natural := 2**backoff_exp_max_c - 1;
  constant backoff_msb_c : natural := backoff_exp_max_c - 1;
  -- Second tap of the x^10 + x^7 + 1 maximal length polynomial.
  constant lfsr_tap_c : natural := backoff_exp_max_c - 4;

  -- Replay buffer.  Only a collision within the slot time is retried,
  -- so only a slot time worth of frame bytes may ever have to be
  -- replayed.  One extra byte because the byte counter saturates one
  -- byte load after the slot time elapses.
  constant log_depth_c : natural := slot_bits_c / 8 + 1;

  -- Pseudo-random source for the backoff.  Seed is arbitrary but must
  -- not be zero.  Receive carrier is mixed in the feedback so that two
  -- peers whose clocks and line events are unrelated do not draw the
  -- same sequence.  Mixing is inhibited on the only state that could
  -- otherwise reach the all-zero lockup state.
  constant lfsr_seed_c : std_ulogic_vector(backoff_exp_max_c-1 downto 0)
    := "1001011011";
  constant lfsr_tail_zero_c : std_ulogic_vector(backoff_msb_c-1 downto 0)
    := (others => '0');

  type state_t is (
    ST_RESET,
    -- Idle, pacing the flit interface, waiting for a frame.
    ST_IDLE,
    -- Frame bits are handed over to the manchester transmitter.
    ST_DATA,
    -- Jam sequence is handed over to the manchester transmitter.
    ST_JAM,
    -- Last bit cell is on the line.
    ST_LAST,
    -- End of frame marker.
    ST_TP_IDL,
    -- Waiting out the backoff, then the medium, before retransmitting.
    ST_BACKOFF,
    -- Consuming and discarding the rest of an abandoned frame.
    ST_DRAIN
    );

  -- What to do once the line has been released.
  type pending_t is (
    PEND_NONE,
    PEND_RETRY,
    PEND_DRAIN
    );

  type regs_t is
  record
    state : state_t;
    pending : pending_t;

    byte_ctr : natural range 0 to byte_cycles_c-1;
    -- Byte time boundary, one cycle after byte_ctr wrapped, i.e. on
    -- the cycle where a flit issued at the wrap point is sampled.
    tick : std_ulogic;

    nlp_ctr : natural range 0 to nlp_period_cycles_c-1;
    nlp_pulse : natural range 0 to nlp_cycles_c;
    pulse_ctr : natural range 0 to tp_idl_cycles_c-1;

    -- Medium busy timer.  Reloaded while carrier is asserted, so it
    -- reaches zero one inter-frame gap after carrier fell.
    defer_ctr : natural range 0 to ipg_cycles_c-1;

    -- Time left in the slot time of the current attempt while
    -- transmitting, backoff slot timer while waiting.
    slot_ctr : natural range 0 to slot_cycles_c-1;
    backoff_slots : natural range 0 to backoff_max_c;
    -- Range the next backoff is drawn in, one more bit per collision
    -- this frame suffered, saturating.
    backoff_mask : unsigned(backoff_exp_max_c-1 downto 0);
    -- Collisions this frame already suffered.
    attempt : natural range 0 to attempt_max_c-1;
    lfsr : std_ulogic_vector(backoff_exp_max_c-1 downto 0);

    -- Asserted for the cycle where flit_i is sampled.
    fetch : std_ulogic;
    -- Next byte of the frame, prefetched during transmission of the
    -- current one.
    pre_data : byte;
    pre_valid : std_ulogic;
    pre_full : boolean;

    -- Bytes of the current frame already handed to the line, kept for
    -- retransmission.  log_len saturates, rd_ptr equals log_len unless
    -- a replay is in progress.
    log : byte_string(0 to log_depth_c-1);
    log_len : natural range 0 to log_depth_c;
    rd_ptr : natural range 0 to log_depth_c;

    shreg : std_ulogic_vector(7 downto 0);
    bit_index : natural range 0 to 7;
    jam_ctr : natural range 0 to jam_bytes_c-1;
    line_valid : std_ulogic;

    collision : std_ulogic;
    late_collision : std_ulogic;
    excessive_collision : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal line_ready_s, line_active_s, line_data_s : std_ulogic;

begin

  assert clock_i_hz_c mod (2 * signal_hz_c) = 0
    report "clock_i_hz_c must be a multiple of 20 MHz"
    severity failure;

  encoder: nsl_line_coding.manchester.manchester_transmitter
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      signal_hz_c => signal_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      ready_o => line_ready_s,
      valid_i => r.line_valid,
      bit_i => r.shreg(0),

      active_o => line_active_s,
      data_o => line_data_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.fetch <= '0';
      r.tick <= '0';
      r.pre_full <= false;
      r.line_valid <= '0';
      r.nlp_pulse <= 0;
      r.lfsr <= lfsr_seed_c;
      r.collision <= '0';
      r.late_collision <= '0';
      r.excessive_collision <= '0';
    end if;
  end process;

  transition: process(r, flit_i, carrier_i, line_ready_s, line_active_s) is
    variable medium_free_v : boolean;
    variable backoff_v : natural range 0 to backoff_max_c;
    variable abandon_v : pending_t;
  begin
    rin <= r;

    rin.fetch <= '0';
    rin.tick <= '0';
    rin.collision <= '0';
    rin.late_collision <= '0';
    rin.excessive_collision <= '0';

    -- Medium is ours to take one inter-frame gap after carrier fell.
    medium_free_v := carrier_i = '0' and r.defer_ctr = 0;

    -- Backoff of the next attempt, if the frame collides now.
    backoff_v := to_integer(unsigned(r.lfsr) and r.backoff_mask);

    -- Whether an abandoned frame still has flits to discard.
    if r.pre_full and r.pre_valid = '0' then
      abandon_v := PEND_NONE;
    else
      abandon_v := PEND_DRAIN;
    end if;

    if r.nlp_ctr /= 0 then
      rin.nlp_ctr <= r.nlp_ctr - 1;
    end if;

    if r.nlp_pulse /= 0 then
      rin.nlp_pulse <= r.nlp_pulse - 1;
    end if;

    if carrier_i = '1' then
      rin.defer_ctr <= ipg_cycles_c - 1;
    elsif r.defer_ctr /= 0 then
      rin.defer_ctr <= r.defer_ctr - 1;
    end if;

    if r.lfsr(backoff_msb_c-1 downto 0) = lfsr_tail_zero_c then
      rin.lfsr <= r.lfsr(backoff_msb_c-1 downto 0)
                  & (r.lfsr(backoff_msb_c) xor r.lfsr(lfsr_tap_c));
    else
      rin.lfsr <= r.lfsr(backoff_msb_c-1 downto 0)
                  & (r.lfsr(backoff_msb_c) xor r.lfsr(lfsr_tap_c) xor carrier_i);
    end if;

    if r.byte_ctr /= 0 then
      rin.byte_ctr <= r.byte_ctr - 1;
    else
      rin.byte_ctr <= byte_cycles_c - 1;
      rin.tick <= '1';
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.byte_ctr <= byte_cycles_c - 1;
        rin.nlp_ctr <= nlp_period_cycles_c - 1;
        rin.defer_ctr <= ipg_cycles_c - 1;
        rin.pending <= PEND_NONE;
        rin.pre_full <= false;
        rin.line_valid <= '0';
        rin.log_len <= 0;
        rin.rd_ptr <= 0;
        rin.attempt <= 0;
        rin.backoff_mask <= to_unsigned(1, backoff_exp_max_c);

      when ST_IDLE =>
        if r.byte_ctr = 0 and medium_free_v then
          rin.fetch <= '1';
        end if;

        -- Frames and link pulses may only start on a byte time
        -- boundary.  This way a link pulse never delays flit
        -- interface pacing, and never overlaps a frame.
        if r.tick = '1' then
          if r.fetch = '1' and flit_i.valid = '1' then
            rin.shreg <= flit_i.data;
            rin.log(0) <= flit_i.data;
            rin.log_len <= 1;
            rin.rd_ptr <= 1;
            rin.bit_index <= 0;
            rin.line_valid <= '1';
            rin.pre_full <= false;
            rin.attempt <= 0;
            rin.backoff_mask <= to_unsigned(1, backoff_exp_max_c);
            rin.pending <= PEND_NONE;
            rin.slot_ctr <= slot_cycles_c - 1;
            rin.state <= ST_DATA;
            rin.nlp_ctr <= nlp_period_cycles_c - 1;
          elsif r.nlp_ctr = 0 then
            rin.nlp_pulse <= nlp_cycles_c;
            rin.nlp_ctr <= nlp_period_cycles_c - 1;
          end if;
        end if;

      when ST_DATA =>
        -- Link pulse timer only counts time the line is idle.
        rin.nlp_ctr <= nlp_period_cycles_c - 1;
        rin.byte_ctr <= byte_cycles_c - 1;

        if r.slot_ctr /= 0 then
          rin.slot_ctr <= r.slot_ctr - 1;
        end if;

        if r.fetch = '1' then
          rin.pre_data <= flit_i.data;
          rin.pre_valid <= flit_i.valid;
          rin.pre_full <= true;
        elsif not r.pre_full then
          rin.fetch <= '1';
        end if;

        if line_ready_s = '1' then
          if r.bit_index /= 7 then
            rin.bit_index <= r.bit_index + 1;
            rin.shreg <= '0' & r.shreg(7 downto 1);
          elsif r.rd_ptr /= r.log_len then
            -- Replaying a byte already fetched on a previous attempt.
            rin.shreg <= r.log(r.rd_ptr);
            rin.rd_ptr <= r.rd_ptr + 1;
            rin.bit_index <= 0;
          else
            assert r.pre_full
              report "Flit interface did not keep up with the line"
              severity failure;

            rin.pre_full <= false;
            if r.pre_valid = '1' then
              rin.shreg <= r.pre_data;
              rin.bit_index <= 0;
              if r.log_len /= log_depth_c then
                rin.log(r.log_len) <= r.pre_data;
                rin.log_len <= r.log_len + 1;
                rin.rd_ptr <= r.log_len + 1;
              end if;
            else
              rin.line_valid <= '0';
              rin.pending <= PEND_NONE;
              rin.state <= ST_LAST;
            end if;
          end if;
        end if;

        -- Collision handling overrides whatever the frame was about
        -- to do, but not the flit sampled on this very cycle.
        if collision_detect_c and carrier_i = '1' then
          rin.collision <= '1';
          rin.fetch <= '0';
          rin.shreg <= jam_byte_c;
          rin.bit_index <= 0;
          rin.jam_ctr <= jam_bytes_c - 1;
          rin.line_valid <= '1';
          rin.state <= ST_JAM;

          if r.slot_ctr = 0 then
            rin.late_collision <= '1';
            rin.pending <= abandon_v;
          elsif r.attempt = attempt_max_c - 1 then
            rin.excessive_collision <= '1';
            rin.pending <= abandon_v;
          else
            rin.attempt <= r.attempt + 1;
            rin.backoff_slots <= backoff_v;
            rin.backoff_mask <= r.backoff_mask(backoff_msb_c-1 downto 0) & '1';
            rin.pending <= PEND_RETRY;
          end if;
        end if;

      when ST_JAM =>
        rin.nlp_ctr <= nlp_period_cycles_c - 1;
        rin.byte_ctr <= byte_cycles_c - 1;

        if line_ready_s = '1' then
          if r.bit_index /= 7 then
            rin.bit_index <= r.bit_index + 1;
            rin.shreg <= '0' & r.shreg(7 downto 1);
          elsif r.jam_ctr /= 0 then
            rin.jam_ctr <= r.jam_ctr - 1;
            rin.shreg <= jam_byte_c;
            rin.bit_index <= 0;
          else
            rin.line_valid <= '0';
            rin.state <= ST_LAST;
          end if;
        end if;

      when ST_LAST =>
        rin.nlp_ctr <= nlp_period_cycles_c - 1;
        rin.byte_ctr <= byte_cycles_c - 1;

        if line_active_s = '0' then
          rin.state <= ST_TP_IDL;
          rin.pulse_ctr <= tp_idl_cycles_c - 1;
        end if;

      when ST_TP_IDL =>
        rin.nlp_ctr <= nlp_period_cycles_c - 1;

        if r.pulse_ctr /= 0 then
          rin.pulse_ctr <= r.pulse_ctr - 1;
          rin.byte_ctr <= byte_cycles_c - 1;
        else
          rin.byte_ctr <= byte_cycles_c - 1;
          case r.pending is
            when PEND_NONE =>
              rin.state <= ST_IDLE;
            when PEND_RETRY =>
              rin.state <= ST_BACKOFF;
              rin.slot_ctr <= slot_cycles_c - 1;
            when PEND_DRAIN =>
              rin.state <= ST_DRAIN;
              rin.pre_full <= false;
          end case;
        end if;

      when ST_BACKOFF =>
        if r.backoff_slots /= 0 then
          if r.slot_ctr /= 0 then
            rin.slot_ctr <= r.slot_ctr - 1;
          else
            rin.slot_ctr <= slot_cycles_c - 1;
            rin.backoff_slots <= r.backoff_slots - 1;
          end if;
        elsif r.tick = '1' then
          if medium_free_v then
            rin.shreg <= r.log(0);
            rin.rd_ptr <= 1;
            rin.bit_index <= 0;
            rin.line_valid <= '1';
            rin.pending <= PEND_NONE;
            rin.slot_ctr <= slot_cycles_c - 1;
            rin.state <= ST_DATA;
            rin.nlp_ctr <= nlp_period_cycles_c - 1;
          elsif r.nlp_ctr = 0 then
            rin.nlp_pulse <= nlp_cycles_c;
            rin.nlp_ctr <= nlp_period_cycles_c - 1;
          end if;
        end if;

      when ST_DRAIN =>
        if r.byte_ctr = 0 then
          rin.fetch <= '1';
        end if;

        if r.tick = '1' and r.nlp_ctr = 0 then
          rin.nlp_pulse <= nlp_cycles_c;
          rin.nlp_ctr <= nlp_period_cycles_c - 1;
        end if;

        if r.fetch = '1' and flit_i.valid = '0' then
          rin.state <= ST_IDLE;
          rin.byte_ctr <= byte_cycles_c - 1;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    ready_o <= r.fetch;
    collision_o <= r.collision;
    late_collision_o <= r.late_collision;
    excessive_collision_o <= r.excessive_collision;

    case r.state is
      when ST_DATA | ST_JAM | ST_LAST | ST_TP_IDL =>
        transmitting_o <= '1';

      when others =>
        transmitting_o <= '0';
    end case;
  end process;

  mealy: process(r, line_active_s, line_data_s) is
  begin
    case r.state is
      when ST_DATA | ST_JAM =>
        if line_active_s = '1' then
          tx_p_o <= line_data_s;
          tx_n_o <= not line_data_s;
          tx_en_o <= '1';
        else
          -- Waiting for the encoder to start, pads stay released.
          tx_p_o <= '0';
          tx_n_o <= '0';
          tx_en_o <= '0';
        end if;

      when ST_LAST =>
        -- TP_IDL starts on the very cycle the last bit cell ends.
        if line_active_s = '1' then
          tx_p_o <= line_data_s;
          tx_n_o <= not line_data_s;
        else
          tx_p_o <= '1';
          tx_n_o <= '0';
        end if;
        tx_en_o <= '1';

      when ST_TP_IDL =>
        tx_p_o <= '1';
        tx_n_o <= '0';
        tx_en_o <= '1';

      when others =>
        -- Normal link pulse, may happen in any state where the line
        -- is ours and no frame is on it.
        if r.nlp_pulse /= 0 then
          tx_p_o <= '1';
          tx_n_o <= '0';
          tx_en_o <= '1';
        else
          tx_p_o <= '0';
          tx_n_o <= '0';
          tx_en_o <= '0';
        end if;
    end case;
  end process;

end architecture;
