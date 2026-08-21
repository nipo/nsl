library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Stimulus, emulated ingress ports and egress checkers around one
-- switching_fabric instance.
--
-- Every frame is self-describing: byte 0 holds the ingress port it was
-- injected on, byte 1 a sequence number, byte 2 the total length, the
-- rest is derived from those. An egress checker therefore rebuilds the
-- frame it should have received out of the frame it did receive, and
-- any lost, duplicated, reordered or mixed-up beat shows up as a
-- content or length mismatch.
entity fabric_test is
  generic(
    name_c: string;
    byte_count_c: natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out std_ulogic
    );
end entity;

architecture beh of fabric_test is

  constant port_count_c: natural := 4;
  constant max_len_c: natural := 64;

  constant switch_cfg_c: nsl_inet.switching.config_t
    := nsl_inet.switching.config(byte_count => byte_count_c,
                                 port_count => port_count_c,
                                 buffer_bytes_l2 => 11);
  constant frame_cfg_c: config_t := nsl_inet.switching.internal_config(switch_cfg_c);
  constant out_cfg_c: config_t := nsl_inet.switching.port_config(switch_cfg_c);

  subtype port_mask_t is nsl_inet.switching.port_mask_t;
  subtype forward_req_vector is nsl_inet.switching.forward_req_vector;
  subtype forward_ack_vector is nsl_inet.switching.forward_ack_vector;

  constant no_port_c: port_mask_t := (others => '0');
  constant all_ports_c: std_ulogic_vector(0 to port_count_c-1) := (others => '1');
  constant full_keep_c: std_ulogic_vector(0 to byte_count_c-1) := (others => '1');
  constant good_frame_c: std_ulogic_vector(0 downto 0) := "0";

  type natural_vector is array(natural range <>) of natural;
  subtype port_natural_vector is natural_vector(0 to port_count_c-1);
  type port_natural_matrix is array(natural range <>) of port_natural_vector;
  type mask_vector is array(natural range <>) of port_mask_t;
  subtype history_t is string(1 to 32);
  type history_vector is array(natural range <>) of history_t;

  constant no_history_c: history_t := (others => '.');

  -- Base for the frame payload, xored with a per-frame value.
  constant pattern_c: byte_string
    := from_hex("0f1e2d3c4b5a69788796a5b4c3d2e1f000112233445566778899aabbccddeeff");

  function frame_gen(source: natural;
                     seq: natural;
                     len: natural) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    assert len >= 3 and len <= max_len_c
      report "Frame length out of range"
      severity failure;

    for i in ret'range
    loop
      ret(i) := pattern_c(i mod pattern_c'length)
                xor to_byte((source * 37 + seq * 11 + i / pattern_c'length) mod 256);
    end loop;

    ret(0) := to_byte(source);
    ret(1) := to_byte(seq);
    ret(2) := to_byte(len);

    return ret;
  end function;

  function to_mask(v: std_ulogic_vector) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
    alias xv: std_ulogic_vector(0 to v'length-1) is v;
  begin
    ret(0 to v'length-1) := xv;
    return ret;
  end function;

  -- DUT interface
  signal frame_m_s: master_vector(0 to port_count_c-1);
  signal frame_s_s: slave_vector(0 to port_count_c-1);
  signal fwd_req_s: forward_req_vector(0 to port_count_c-1);
  signal fwd_ack_s: forward_ack_vector(0 to port_count_c-1);
  signal out_m_s: master_vector(0 to port_count_c-1);
  signal out_s_s: slave_vector(0 to port_count_c-1);

  -- Stimulus, driven by the control process, latched by the ingress
  -- emulators on the stim_start_s pulse.
  signal stim_start_s: std_ulogic_vector(0 to port_count_c-1);
  signal stim_seq_s, stim_len_s, stim_count_s: port_natural_vector;
  signal stim_mask_s: mask_vector(0 to port_count_c-1);

  -- Ingress emulator status
  signal ing_idle_s: std_ulogic_vector(0 to port_count_c-1);
  -- [ingress][egress]
  signal taken_count_s: port_natural_matrix(0 to port_count_c-1);
  -- Cycle of the last taken pulse, [ingress][egress]
  signal taken_cycle_s: port_natural_matrix(0 to port_count_c-1);

  -- Egress checker status
  signal rx_count_s: port_natural_vector;
  -- [egress][ingress]
  signal rx_from_s: port_natural_matrix(0 to port_count_c-1);
  signal rx_source_s: port_natural_vector;
  -- Cycle stamps of the first and last beat of the last complete frame
  signal rx_first_s, rx_last_s: port_natural_vector;
  signal rx_history_s: history_vector(0 to port_count_c-1);

  -- 0: always ready, 1: ready one cycle out of three, 2: never ready
  signal ready_mode_s: port_natural_vector;

  signal cycle_s: natural;

begin

  dut: nsl_inet.switching.switching_fabric
    generic map(
      config_c => switch_cfg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      frame_i => frame_m_s,
      frame_o => frame_s_s,
      forward_i => fwd_req_s,
      forward_o => fwd_ack_s,

      out_o => out_m_s,
      out_i => out_s_s
      );

  clock_counter: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      cycle_s <= 0;
    elsif rising_edge(clock_i) then
      cycle_s <= cycle_s + 1;
    end if;
  end process;

  ingress_gen: for ingress in 0 to port_count_c-1 generate
    -- Emulated ingress port: holds one head-of-queue frame, announces
    -- the set of egress ports it still has to reach, streams the frame
    -- from its first beat, and rewinds on every taken pulse.
    emulator: process(clock_i, reset_n_i) is
      variable frame_v: byte_string(0 to max_len_c-1);
      variable mask_v, pending_v: port_mask_t;
      variable seq_v, len_v, beat_count_v, pos_v, remaining_v: natural;
      variable data_v: byte_string(0 to byte_count_c-1);
      variable keep_v: std_ulogic_vector(0 to byte_count_c-1);
      variable base_v, taken_v: natural;
    begin
      if reset_n_i = '0' then
        mask_v := no_port_c;
        pending_v := no_port_c;
        seq_v := 0;
        len_v := 3;
        beat_count_v := 0;
        pos_v := 0;
        remaining_v := 0;
        frame_m_s(ingress) <= transfer_defaults(frame_cfg_c);
        fwd_req_s(ingress).valid <= '0';
        fwd_req_s(ingress).mask <= no_port_c;
        ing_idle_s(ingress) <= '1';
        taken_count_s(ingress) <= (others => 0);
        taken_cycle_s(ingress) <= (others => 0);
      elsif rising_edge(clock_i) then
        if stim_start_s(ingress) = '1' then
          assert pending_v = no_port_c and remaining_v = 0
            report name_c&": ingress "&to_string(ingress)&" armed while busy"
            severity failure;

          mask_v := stim_mask_s(ingress);
          seq_v := stim_seq_s(ingress);
          len_v := stim_len_s(ingress);
          remaining_v := stim_count_s(ingress);
          beat_count_v := (len_v + byte_count_c - 1) / byte_count_c;
          frame_v(0 to len_v-1) := frame_gen(ingress, seq_v, len_v);
          pending_v := mask_v;
          pos_v := 0;
          remaining_v := remaining_v - 1;
        else
          if frame_m_s(ingress).valid = '1' and frame_s_s(ingress).ready = '1' then
            assert pos_v < beat_count_v
              report name_c&": ingress "&to_string(ingress)&" beat accepted past end of frame"
              severity failure;
            pos_v := pos_v + 1;
          end if;

          taken_v := 0;
          for egress in 0 to port_count_c-1
          loop
            if fwd_ack_s(ingress).taken(egress) = '1' then
              taken_v := taken_v + 1;
              assert pending_v(egress) = '1'
                report name_c&": ingress "&to_string(ingress)
                &" acked for egress "&to_string(egress)&" which is not pending"
                severity failure;
              assert pos_v = beat_count_v
                report name_c&": ingress "&to_string(ingress)
                &" acked for egress "&to_string(egress)&" before end of frame"
                severity failure;
              pending_v(egress) := '0';
              pos_v := 0;
              taken_count_s(ingress)(egress) <= taken_count_s(ingress)(egress) + 1;
              taken_cycle_s(ingress)(egress) <= cycle_s;
            end if;
          end loop;

          assert taken_v <= 1
            report name_c&": ingress "&to_string(ingress)&" acked by several egress ports at once"
            severity failure;

          if pending_v = no_port_c and remaining_v /= 0 then
            seq_v := seq_v + 1;
            frame_v(0 to len_v-1) := frame_gen(ingress, seq_v, len_v);
            pending_v := mask_v;
            pos_v := 0;
            remaining_v := remaining_v - 1;
          end if;
        end if;

        if pending_v = no_port_c then
          fwd_req_s(ingress).valid <= '0';
          fwd_req_s(ingress).mask <= no_port_c;
        else
          fwd_req_s(ingress).valid <= '1';
          fwd_req_s(ingress).mask <= pending_v;
        end if;

        if pending_v = no_port_c and remaining_v = 0 then
          ing_idle_s(ingress) <= '1';
        else
          ing_idle_s(ingress) <= '0';
        end if;

        if pending_v /= no_port_c and pos_v < beat_count_v then
          base_v := pos_v * byte_count_c;
          data_v := (others => to_byte(0));
          keep_v := (others => '0');
          for k in 0 to byte_count_c-1
          loop
            if base_v + k < len_v then
              data_v(k) := frame_v(base_v + k);
              keep_v(k) := '1';
            end if;
          end loop;

          frame_m_s(ingress) <= transfer(frame_cfg_c,
                                         bytes => data_v,
                                         keep => keep_v,
                                         last => pos_v = beat_count_v - 1);
        else
          frame_m_s(ingress) <= transfer_defaults(frame_cfg_c);
        end if;
      end if;
    end process;
  end generate;

  egress_gen: for egress in 0 to port_count_c-1 generate
    -- Egress checker: drives ready according to ready_mode_s,
    -- reassembles the frame and matches it against what the frame
    -- header says it should be.
    checker: process(clock_i, reset_n_i) is
      variable acc_v: byte_string(0 to max_len_c-1);
      variable count_v, first_v, phase_v, frame_no_v: natural;
      variable source_v, seq_v, len_v: natural;
      variable data_v: byte_string(0 to byte_count_c-1);
      variable keep_v: std_ulogic_vector(0 to byte_count_c-1);
      variable history_v: history_t;
      variable ready_v: boolean;
    begin
      if reset_n_i = '0' then
        count_v := 0;
        first_v := 0;
        phase_v := 0;
        frame_no_v := 0;
        history_v := no_history_c;
        out_s_s(egress) <= accept(out_cfg_c, false);
        rx_count_s(egress) <= 0;
        rx_from_s(egress) <= (others => 0);
        rx_source_s(egress) <= 0;
        rx_first_s(egress) <= 0;
        rx_last_s(egress) <= 0;
        rx_history_s(egress) <= no_history_c;
      elsif rising_edge(clock_i) then
        if is_valid(out_cfg_c, out_m_s(egress)) and out_s_s(egress).ready = '1' then
          data_v := bytes(out_cfg_c, out_m_s(egress));
          keep_v := keep(out_cfg_c, out_m_s(egress));

          assert_equal(name_c, "egress "&to_string(egress)&" user flag",
                       user(out_cfg_c, out_m_s(egress)), good_frame_c, FAILURE);

          assert keep_v(0) = '1'
            report name_c&": egress "&to_string(egress)&" beat with no kept byte"
            severity failure;
          for k in 1 to byte_count_c-1
          loop
            assert keep_v(k) = '0' or keep_v(k-1) = '1'
              report name_c&": egress "&to_string(egress)&" beat with holes in keep"
              severity failure;
          end loop;
          if not is_last(out_cfg_c, out_m_s(egress)) then
            assert keep_v = full_keep_c
              report name_c&": egress "&to_string(egress)&" partial beat before end of frame"
              severity failure;
          end if;

          if count_v = 0 then
            first_v := cycle_s;
          end if;

          for k in 0 to byte_count_c-1
          loop
            if keep_v(k) = '1' then
              assert count_v < max_len_c
                report name_c&": egress "&to_string(egress)&" frame longer than expected"
                severity failure;
              acc_v(count_v) := data_v(k);
              count_v := count_v + 1;
            end if;
          end loop;

          if is_last(out_cfg_c, out_m_s(egress)) then
            source_v := to_integer(acc_v(0));
            seq_v := to_integer(acc_v(1));
            len_v := to_integer(acc_v(2));

            assert source_v < port_count_c
              report name_c&": egress "&to_string(egress)
              &" frame from unknown ingress "&to_string(source_v)
              severity failure;
            assert_equal(name_c, "egress "&to_string(egress)&" frame length",
                         count_v, len_v, FAILURE);
            assert_equal(name_c, "egress "&to_string(egress)&" frame content",
                         acc_v(0 to count_v-1), frame_gen(source_v, seq_v, len_v),
                         FAILURE);

            frame_no_v := frame_no_v + 1;
            assert frame_no_v <= history_v'length
              report name_c&": egress "&to_string(egress)&" history overflow"
              severity failure;
            history_v(frame_no_v) := character'val(character'pos('0') + source_v);

            rx_count_s(egress) <= frame_no_v;
            rx_from_s(egress)(source_v) <= rx_from_s(egress)(source_v) + 1;
            rx_source_s(egress) <= source_v;
            rx_first_s(egress) <= first_v;
            rx_last_s(egress) <= cycle_s;
            rx_history_s(egress) <= history_v;

            count_v := 0;
          end if;
        end if;

        if phase_v = 2 then
          phase_v := 0;
        else
          phase_v := phase_v + 1;
        end if;

        case ready_mode_s(egress) is
          when 0 =>
            ready_v := true;
          when 1 =>
            ready_v := phase_v = 0;
          when 2 =>
            ready_v := false;
          when others =>
            assert false
              report name_c&": unknown ready mode"
              severity failure;
        end case;

        out_s_s(egress) <= accept(out_cfg_c, ready_v);
      end if;
    end process;
  end generate;

  -- An ingress frame buffer has a single read port, so the beats it
  -- hands out between two acknowledges are exactly one frame, taken by
  -- exactly one egress port. Two egress ports draining the same
  -- ingress port at once show up either as two acknowledges in one
  -- cycle, or as an acknowledge for a run of beats that has already
  -- been acknowledged. The egress-side content checks catch the beats
  -- the two readers stole from each other.
  --
  -- This watches the ingress boundary rather than out_o: the egress
  -- register slices keep delivering a frame after the ingress read
  -- port has been handed over, so an out_o-side overlap is not a
  -- violation.
  exclusivity: process(clock_i, reset_n_i) is
    variable complete_v: std_ulogic_vector(0 to port_count_c-1);
    variable taken_v: natural;
  begin
    if reset_n_i = '0' then
      complete_v := (others => '0');
    elsif rising_edge(clock_i) then
      for ingress in 0 to port_count_c-1
      loop
        taken_v := 0;
        for egress in 0 to port_count_c-1
        loop
          if fwd_ack_s(ingress).taken(egress) = '1' then
            taken_v := taken_v + 1;
          end if;
        end loop;

        if is_valid(frame_cfg_c, frame_m_s(ingress)) and frame_s_s(ingress).ready = '1' then
          assert complete_v(ingress) = '0'
            report name_c&": ingress "&to_string(ingress)
            &" read past the end of a frame that is not acknowledged yet"
            severity failure;
          if is_last(frame_cfg_c, frame_m_s(ingress)) then
            complete_v(ingress) := '1';
          end if;
        end if;

        if taken_v /= 0 then
          assert taken_v = 1
            report name_c&": ingress "&to_string(ingress)
            &" acknowledged by "&to_string(taken_v)&" egress ports in one cycle"
            severity failure;
          assert complete_v(ingress) = '1'
            report name_c&": ingress "&to_string(ingress)
            &" acknowledged without having handed out a complete frame"
            severity failure;
          complete_v(ingress) := '0';
        end if;
      end loop;
    end if;
  end process;

  control: process is
    variable base_v: port_natural_vector;
    variable first_v, second_v, stamp_v, target_v: natural;
    variable history_v: history_t;

    procedure tick(count: natural := 1) is
    begin
      for i in 1 to count
      loop
        wait until falling_edge(clock_i);
      end loop;
    end procedure;

    procedure arm(ingress: natural;
                  seq: natural;
                  len: natural;
                  mask: std_ulogic_vector;
                  count: natural := 1) is
    begin
      stim_seq_s(ingress) <= seq;
      stim_len_s(ingress) <= len;
      stim_count_s(ingress) <= count;
      stim_mask_s(ingress) <= to_mask(mask);
    end procedure;

    procedure fire(starts: std_ulogic_vector) is
    begin
      wait until falling_edge(clock_i);
      stim_start_s <= starts;
      wait until falling_edge(clock_i);
      stim_start_s <= (others => '0');
    end procedure;

    procedure wait_idle(limit: natural) is
      variable n: natural := 0;
    begin
      while ing_idle_s /= all_ports_c
      loop
        wait until falling_edge(clock_i);
        n := n + 1;
        assert n < limit
          report name_c&": timeout waiting for ingress ports to drain"
          severity failure;
      end loop;
      -- Ingress ports go idle on the last acknowledge, the egress
      -- register slices still have to drain what they hold.
      tick(24);
    end procedure;

    procedure wait_rx(egress: natural;
                      target: natural;
                      limit: natural) is
      variable n: natural := 0;
    begin
      while rx_count_s(egress) < target
      loop
        wait until falling_edge(clock_i);
        n := n + 1;
        assert n < limit
          report name_c&": timeout waiting for "&to_string(target)
          &" frames on egress "&to_string(egress)
          severity failure;
      end loop;
    end procedure;

    procedure wait_rx_from(egress: natural;
                           ingress: natural;
                           target: natural;
                           limit: natural) is
      variable n: natural := 0;
    begin
      while rx_from_s(egress)(ingress) < target
      loop
        wait until falling_edge(clock_i);
        n := n + 1;
        assert n < limit
          report name_c&": timeout waiting for "&to_string(target)
          &" frames from ingress "&to_string(ingress)
          &" on egress "&to_string(egress)
          severity failure;
      end loop;
    end procedure;

    procedure check_delivery(ingress: natural;
                             egress: natural;
                             count: natural) is
    begin
      assert_equal(name_c, "frames received on egress "&to_string(egress)
                   &" from ingress "&to_string(ingress),
                   rx_from_s(egress)(ingress), count, FAILURE);
      assert_equal(name_c, "takens pulsed to ingress "&to_string(ingress)
                   &" for egress "&to_string(egress),
                   taken_count_s(ingress)(egress), count, FAILURE);
    end procedure;

  begin
    done_o <= '0';
    stim_start_s <= (others => '0');
    stim_seq_s <= (others => 0);
    stim_len_s <= (others => 3);
    stim_count_s <= (others => 0);
    stim_mask_s <= (others => no_port_c);
    ready_mode_s <= (others => 0);

    wait until reset_n_i = '1';
    tick(4);

    -- 1. One unicast copy, ingress 0 to egress 2.
    arm(0, 1, 7, "0010");
    fire("1000");
    wait_idle(400);

    check_delivery(0, 2, 1);
    for egress in 0 to port_count_c-1
    loop
      if egress = 2 then
        assert_equal(name_c, "frame count on egress 2", rx_count_s(egress), 1, FAILURE);
      else
        assert_equal(name_c, "frame count on egress "&to_string(egress),
                     rx_count_s(egress), 0, FAILURE);
        assert_equal(name_c, "takens pulsed to ingress 0 for egress "&to_string(egress),
                     taken_count_s(0)(egress), 0, FAILURE);
      end if;
    end loop;

    -- 2. Two independent copies must overlap in time.
    arm(0, 2, 41, "0100");
    arm(2, 3, 43, "0001");
    fire("1010");
    wait_idle(600);

    check_delivery(0, 1, 1);
    check_delivery(2, 3, 1);
    assert rx_first_s(1) <= rx_last_s(3) and rx_first_s(3) <= rx_last_s(1)
      report name_c&": copies to egress 1 and 3 did not overlap in time"
      severity failure;

    -- 3. Two ingress ports contending for one egress port get
    -- serialized, and a saturating ingress port does not starve the
    -- other one.
    base_v := rx_count_s;
    arm(0, 4, 23, "0100", count => 4);
    arm(2, 5, 29, "0100", count => 2);
    fire("1010");
    wait_rx(1, base_v(1) + 1, 600);
    first_v := rx_source_s(1);
    wait_rx(1, base_v(1) + 2, 600);
    second_v := rx_source_s(1);
    wait_idle(2000);

    assert first_v /= second_v
      report name_c&": egress 1 served the same ingress port twice in a row under contention"
      severity failure;
    check_delivery(0, 1, 5);
    check_delivery(2, 1, 2);

    history_v := rx_history_s(1);
    target_v := 0;
    for i in 1 to 4
    loop
      if history_v(base_v(1) + i) = '2' then
        target_v := target_v + 1;
      end if;
    end loop;
    assert_equal(name_c, "frames of ingress 2 among the first four served under contention",
                 target_v, 2, FAILURE);

    -- 4. Multicast: one frame from ingress 1 to three egress ports,
    -- delivered as three serial copies.
    arm(1, 6, 37, "1011");
    fire("0100");
    wait_idle(1500);

    check_delivery(1, 0, 1);
    check_delivery(1, 2, 1);
    check_delivery(1, 3, 1);
    check_delivery(1, 1, 0);

    -- 5. Multicast and contention on one of the destinations.
    base_v := rx_count_s;
    arm(1, 7, 31, "1011");
    arm(0, 8, 19, "0010");
    fire("1100");
    wait_idle(2000);

    check_delivery(1, 0, 2);
    check_delivery(1, 2, 2);
    check_delivery(1, 3, 2);
    check_delivery(0, 2, 2);

    -- 6. An egress port locking an ingress port must not let another
    -- egress port stream from it, and the other egress port must be
    -- able to serve another candidate meanwhile.
    base_v := rx_count_s;
    ready_mode_s(0) <= 1;
    arm(1, 9, 61, "1010");
    arm(3, 10, 11, "0010");
    fire("0101");

    wait_rx_from(0, 1, 3, 3000);
    stamp_v := taken_cycle_s(1)(0);
    wait_rx_from(2, 1, 3, 3000);
    -- A copy takes at least one cycle per beat and ends on its
    -- acknowledge, so an acknowledge a whole frame later than the
    -- previous one means the two reads of ingress 1 did not overlap by
    -- a single beat.
    target_v := (61 + byte_count_c - 1) / byte_count_c;
    assert taken_cycle_s(1)(2) >= stamp_v + target_v
      report name_c&": egress 2 read ingress 1 while egress 0 still had it"
      severity failure;

    wait_idle(3000);
    ready_mode_s(0) <= 0;

    check_delivery(1, 0, 3);
    check_delivery(1, 2, 3);
    check_delivery(3, 2, 1);
    assert_equal(name_c, "frames received on egress 2 while an ingress port was locked",
                 rx_count_s(2) - base_v(2), 2, FAILURE);

    -- 7. Stuttering ready on the destination must not break the
    -- stream.
    ready_mode_s(3) <= 1;
    arm(2, 11, 63, "0001", count => 3);
    fire("0010");
    wait_idle(4000);
    ready_mode_s(3) <= 0;

    check_delivery(2, 3, 4);

    log_info(name_c, "delivered "&to_string(rx_count_s(0) + rx_count_s(1)
                                            + rx_count_s(2) + rx_count_s(3))
             &" frame copies");

    done_o <= '1';

    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

begin

  narrow: entity work.fabric_test
    generic map(
      name_c => "fabric 1B",
      byte_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  wide: entity work.fabric_test
    generic map(
      name_c => "fabric 4B",
      byte_count_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
