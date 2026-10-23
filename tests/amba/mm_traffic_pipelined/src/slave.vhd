library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_traffic.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- A memory that behaves like the far end of an interconnect: it takes
-- several addresses ahead of their data, answers reads after a
-- latency, and may stall any channel at random.
--
-- Write data is taken whenever the slave is ready for it, before its
-- address if need be, and is matched to addresses in order.  Every
-- beat is then held against the payload its own address stands for,
-- which pins the association between payload and address that the
-- walk alone cannot see.
--
-- One read beat, at corrupt_address_c, comes back with a bit flipped
-- when that generic is set, so the bench can check the walker sees it.
--
-- It also checks the master keeps a channel's content stable while it
-- is not accepted.
entity slave_model is
  generic(
    config_c: config_t;
    byte_size_l2_c: natural;
    seed_c: natural;
    address_depth_c: positive;
    read_latency_c: natural;
    backpressure_c: boolean;
    random_seed_c: positive;
    corrupt_address_c: integer := -1
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    axi_i: in master_t;
    axi_o: out slave_t;

    write_beats_o: out natural;
    write_bad_o: out natural;
    protocol_errors_o: out natural
    );
end entity;

architecture beh of slave_model is

  constant beat_byte_c: natural := 2 ** config_c.data_bus_width_l2;
  constant word_count_c: natural := 2 ** (byte_size_l2_c - config_c.data_bus_width_l2);
  constant queue_size_c: natural := 4096;
  constant seed_u_c: unsigned(31 downto 0) := to_unsigned(seed_c, 32);

  subtype beat_t is byte_string(0 to beat_byte_c - 1);
  type memory_t is array(natural range <>) of beat_t;

  type command_t is
  record
    addr: natural;
    len_m1: natural;
    ready_at: natural;
  end record;
  type command_queue_t is array(natural range <>) of command_t;

  type data_t is
  record
    bytes: beat_t;
    last: boolean;
  end record;
  type data_queue_t is array(natural range <>) of data_t;

begin

  model: process is
    variable mem: memory_t(0 to word_count_c - 1);
    variable aw_q, ar_q: command_queue_t(0 to queue_size_c - 1);
    variable aw_head, aw_tail, ar_head, ar_tail: natural := 0;
    variable w_q: data_queue_t(0 to queue_size_c - 1);
    variable w_head, w_tail: natural := 0;
    variable w_beat, r_beat: natural := 0;
    variable b_pending: natural := 0;
    variable cycle: natural := 0;

    variable aw_ready, w_ready, ar_ready, b_valid, r_valid: boolean := false;
    variable r_bytes: beat_t;
    variable r_last: boolean;

    variable prev_aw, prev_ar: address_t;
    variable prev_w: write_data_t;
    variable aw_held, w_held, ar_held: boolean := false;

    variable s1, s2: positive;
    variable x: real;
    variable word: natural;
    variable want: beat_t;
    variable write_beats, write_bad, protocol_errors: natural := 0;

    impure function stall return boolean is
    begin
      if not backpressure_c then
        return false;
      end if;
      uniform(s1, s2, x);
      return x < 0.4;
    end function;

  begin
    s1 := random_seed_c;
    s2 := random_seed_c * 7 + 13;

    axi_o.aw <= accept(config_c, false);
    axi_o.w <= accept(config_c, false);
    axi_o.ar <= accept(config_c, false);
    axi_o.b <= write_response(config_c, valid => false);
    axi_o.r <= read_data_defaults(config_c);
    write_beats_o <= 0;
    write_bad_o <= 0;
    protocol_errors_o <= 0;

    wait until reset_n_i = '1';

    loop
      wait until rising_edge(clock_i);
      cycle := cycle + 1;

      -- Content held since last cycle must not have changed.
      if aw_held and axi_i.aw /= prev_aw then
        protocol_errors := protocol_errors + 1;
        report "AW changed before it was accepted" severity error;
      end if;
      if w_held and axi_i.w /= prev_w then
        protocol_errors := protocol_errors + 1;
        report "W changed before it was accepted" severity error;
      end if;
      if ar_held and axi_i.ar /= prev_ar then
        protocol_errors := protocol_errors + 1;
        report "AR changed before it was accepted" severity error;
      end if;

      aw_held := is_valid(config_c, axi_i.aw) and not aw_ready;
      w_held := is_valid(config_c, axi_i.w) and not w_ready;
      ar_held := is_valid(config_c, axi_i.ar) and not ar_ready;
      prev_aw := axi_i.aw;
      prev_w := axi_i.w;
      prev_ar := axi_i.ar;

      if is_valid(config_c, axi_i.aw) and aw_ready then
        aw_q(aw_tail mod queue_size_c) := (
          addr => to_integer(address(config_c, axi_i.aw)),
          len_m1 => to_integer(length_m1(config_c, axi_i.aw, 8)),
          ready_at => 0);
        aw_tail := aw_tail + 1;
      end if;

      if is_valid(config_c, axi_i.w) and w_ready then
        w_q(w_tail mod queue_size_c) := (
          bytes => bytes(config_c, axi_i.w)(0 to beat_byte_c - 1),
          last => is_last(config_c, axi_i.w));
        w_tail := w_tail + 1;
      end if;

      if b_valid and is_ready(config_c, axi_i.b) then
        b_valid := false;
        b_pending := b_pending - 1;
      end if;

      if is_valid(config_c, axi_i.ar) and ar_ready then
        ar_q(ar_tail mod queue_size_c) := (
          addr => to_integer(address(config_c, axi_i.ar)),
          len_m1 => to_integer(length_m1(config_c, axi_i.ar, 8)),
          ready_at => cycle + read_latency_c);
        ar_tail := ar_tail + 1;
      end if;

      if r_valid and is_ready(config_c, axi_i.r) then
        r_valid := false;
        if r_beat = ar_q(ar_head mod queue_size_c).len_m1 then
          r_beat := 0;
          ar_head := ar_head + 1;
        else
          r_beat := r_beat + 1;
        end if;
      end if;

      -- One write beat retired per cycle, once its address is known.
      if aw_head /= aw_tail and w_head /= w_tail then
        word := (aw_q(aw_head mod queue_size_c).addr / beat_byte_c + w_beat)
                mod word_count_c;
        mem(word) := w_q(w_head mod queue_size_c).bytes;
        want := pattern(seed_u_c, to_unsigned(word * beat_byte_c, 32), beat_byte_c);

        write_beats := write_beats + 1;
        if mem(word) /= want then
          write_bad := write_bad + 1;
          if write_bad = 1 then
            report "write at " & to_string(word * beat_byte_c)
              & " carried " & to_string(mem(word))
              & ", the payload of that address is " & to_string(want)
              severity error;
          end if;
        end if;

        if w_q(w_head mod queue_size_c).last
          /= (w_beat = aw_q(aw_head mod queue_size_c).len_m1) then
          protocol_errors := protocol_errors + 1;
          report "WLAST does not match AWLEN" severity error;
        end if;

        if w_beat = aw_q(aw_head mod queue_size_c).len_m1 then
          w_beat := 0;
          aw_head := aw_head + 1;
          b_pending := b_pending + 1;
        else
          w_beat := w_beat + 1;
        end if;
        w_head := w_head + 1;
      end if;

      write_beats_o <= write_beats;
      write_bad_o <= write_bad;
      protocol_errors_o <= protocol_errors;

      wait until falling_edge(clock_i);

      aw_ready := aw_tail - aw_head < address_depth_c and not stall;
      w_ready := w_tail - w_head < queue_size_c and not stall;
      ar_ready := ar_tail - ar_head < address_depth_c and not stall;

      if not b_valid and b_pending /= 0 and not stall then
        b_valid := true;
      end if;

      if not r_valid and ar_head /= ar_tail
        and cycle >= ar_q(ar_head mod queue_size_c).ready_at
        and not stall then
        r_valid := true;
        word := (ar_q(ar_head mod queue_size_c).addr / beat_byte_c + r_beat)
                mod word_count_c;
        r_bytes := mem(word);
        if word * beat_byte_c = corrupt_address_c then
          r_bytes(0) := r_bytes(0) xor x"01";
        end if;
        r_last := r_beat = ar_q(ar_head mod queue_size_c).len_m1;
      end if;

      axi_o.aw <= accept(config_c, aw_ready);
      axi_o.w <= accept(config_c, w_ready);
      axi_o.ar <= accept(config_c, ar_ready);
      axi_o.b <= write_response(config_c, valid => b_valid);
      if r_valid then
        axi_o.r <= read_data(config_c, bytes => r_bytes, last => r_last, valid => true);
      else
        axi_o.r <= read_data_defaults(config_c);
      end if;
    end loop;
  end process;

end architecture;
