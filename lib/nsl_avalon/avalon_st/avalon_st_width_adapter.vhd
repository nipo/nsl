library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, work;
use work.avalon_st.all;
use nsl_logic.bool.all;

-- Width adapter for Avalon-ST. Mirrors the
-- nsl_amba.axi4_stream.axi4_stream_width_adapter shift-register
-- topology: each cycle is a single full-width register update with
-- the new in_dbits-bit chunk inserted at the high end of the
-- accumulator (widening) or peeled off the low end of a wide buffer
-- (narrowing). No barrel shifter on the data path, so this gives
-- short critical paths and scales well to large symbol counts.
--
-- The internal canonical (symbol 0 in the low bits of source.data)
-- means that for partial beats the data emerges in the high bits of
-- the accumulator after fewer than ratio shifts; on early eop the
-- widener therefore enters a ST_PAD state that keeps shifting in
-- zeros until the data has been pushed down to symbol 0. Padding
-- spends one clock per missing slot but introduces no extra logic
-- depth.
entity avalon_st_width_adapter is
  generic(
    in_config_c  : config_t;
    out_config_c : config_t
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in  source_t;
    in_o : out sink_t;

    out_o : out source_t;
    out_i : in  sink_t
    );
begin

  assert in_config_c.data_bits_per_symbol = out_config_c.data_bits_per_symbol
    report "in/out data_bits_per_symbol must match"
    severity failure;
  assert in_config_c.channel_width = out_config_c.channel_width
    report "in/out channel_width must match"
    severity failure;
  assert in_config_c.error_width = out_config_c.error_width
    report "in/out error_width must match"
    severity failure;
  assert in_config_c.packet_user_width = out_config_c.packet_user_width
    report "in/out packet_user_width must match"
    severity failure;
  assert in_config_c.symbol_user_width = out_config_c.symbol_user_width
    report "in/out symbol_user_width must match"
    severity failure;
  assert in_config_c.has_packet = out_config_c.has_packet
    report "in/out has_packet must match"
    severity failure;
  -- has_empty may differ when one side has symbols_per_beat = 1 (its
  -- has_empty is implicit "false" per config()). With matching spb > 1
  -- on both sides, mismatching has_empty would silently truncate
  -- partial-beat information; warn.
  assert in_config_c.has_empty = out_config_c.has_empty
      or in_config_c.symbols_per_beat = 1
      or out_config_c.symbols_per_beat = 1
    report "has_empty mismatch with multi-symbol beats on both sides"
    severity warning;
  assert in_config_c.ready_latency = 0 and out_config_c.ready_latency = 0
    report "width adapter requires ready_latency = 0 on both sides"
    severity failure;
  assert in_config_c.has_ready and out_config_c.has_ready
    report "width adapter requires has_ready on both sides"
    severity failure;
  assert in_config_c.symbols_per_beat = out_config_c.symbols_per_beat
      or (in_config_c.symbols_per_beat < out_config_c.symbols_per_beat
          and (out_config_c.symbols_per_beat mod in_config_c.symbols_per_beat) = 0)
      or (in_config_c.symbols_per_beat > out_config_c.symbols_per_beat
          and (in_config_c.symbols_per_beat mod out_config_c.symbols_per_beat) = 0)
    report "symbols_per_beat must be in an integer ratio"
    severity failure;
end entity;

architecture beh of avalon_st_width_adapter is

  constant bps_c   : positive := in_config_c.data_bits_per_symbol;
  constant suw_c   : natural  := in_config_c.symbol_user_width;
  constant cw_c    : natural  := in_config_c.channel_width;
  constant ew_c    : natural  := in_config_c.error_width;
  constant puw_c   : natural  := in_config_c.packet_user_width;

begin

  -- Matched: same symbols_per_beat on both sides. Pure wire-through.
  matched_gen: if in_config_c.symbols_per_beat = out_config_c.symbols_per_beat generate
    out_o <= in_i;
    in_o  <= out_i;
  end generate;

  -- Widening: out_cfg has more symbols per beat than in_cfg.
  widen_gen: if in_config_c.symbols_per_beat < out_config_c.symbols_per_beat generate

    constant in_spb_c   : positive := in_config_c.symbols_per_beat;
    constant out_spb_c  : positive := out_config_c.symbols_per_beat;
    constant ratio_c    : positive := out_spb_c / in_spb_c;
    constant in_dbits_c : positive := in_spb_c  * bps_c;
    constant out_dbits_c: positive := out_spb_c * bps_c;
    constant in_subits_c : natural := in_spb_c  * suw_c;
    constant out_subits_c: natural := out_spb_c * suw_c;

    constant zero_in_data_c : std_ulogic_vector(in_dbits_c-1 downto 0) := (others => '0');
    constant zero_in_suw_c  : std_ulogic_vector(nsl_logic.bool.if_else(in_subits_c = 0, 1, in_subits_c)-1 downto 0)
                            := (others => '0');

    type state_t is (ST_FORWARD, ST_PAD);

    type regs_t is record
      state       : state_t;
      data        : std_ulogic_vector(out_dbits_c-1 downto 0);
      symbol_user : std_ulogic_vector(nsl_logic.bool.if_else(out_subits_c = 0, 1, out_subits_c)-1 downto 0);
      channel     : std_ulogic_vector(nsl_logic.bool.if_else(cw_c = 0, 1, cw_c)-1 downto 0);
      error       : std_ulogic_vector(nsl_logic.bool.if_else(ew_c = 0, 1, ew_c)-1 downto 0);
      packet_user : std_ulogic_vector(nsl_logic.bool.if_else(puw_c = 0, 1, puw_c)-1 downto 0);
      sop         : std_ulogic;
      filled      : natural range 0 to ratio_c;
      pad_eop_empty: natural range 0 to out_spb_c;
      post        : source_t;
    end record;

    signal r, rin : regs_t;

  begin

    reg: process(clock_i, reset_n_i) is
    begin
      if reset_n_i = '0' then
        r.state    <= ST_FORWARD;
        r.filled   <= 0;
        r.post     <= transfer_defaults(out_config_c);
      elsif rising_edge(clock_i) then
        r <= rin;
      end if;
    end process;

    cb: process(r, in_i, out_i) is
      variable rv     : regs_t;
      variable accept_v : boolean;
      variable shift_v  : boolean;
      variable do_emit_v : boolean;
      variable new_filled : natural;
      variable in_data_v : std_ulogic_vector(in_dbits_c-1 downto 0);
      variable in_suw_v  : std_ulogic_vector(nsl_logic.bool.if_else(in_subits_c = 0, 1, in_subits_c)-1 downto 0);
      variable empty_v   : natural;
      variable eop_now_v : boolean;
    begin
      rv := r;

      -- If the held output beat is being taken this cycle, free the slot.
      if is_ready(out_config_c, out_i) and is_valid(out_config_c, r.post) then
        rv.post.valid := '0';
      end if;

      accept_v   := false;
      shift_v    := false;
      in_data_v  := zero_in_data_c;
      in_suw_v   := zero_in_suw_c;
      do_emit_v  := false;
      eop_now_v  := false;

      case r.state is
        when ST_FORWARD =>
          -- We can accept a new input when either the held output slot
          -- is empty or it will be emptied this cycle.
          if is_valid(in_config_c, in_i)
              and (not is_valid(out_config_c, r.post) or is_ready(out_config_c, out_i))
              and r.state = ST_FORWARD then
            accept_v  := true;
            shift_v   := true;
            in_data_v := in_i.data(in_dbits_c-1 downto 0);
            if in_subits_c /= 0 then
              in_suw_v := in_i.symbol_user(in_subits_c-1 downto 0);
            end if;
            eop_now_v := is_eop(in_config_c, in_i, default => false);

            new_filled := r.filled + 1;

            if new_filled = ratio_c then
              do_emit_v   := true;
            elsif eop_now_v then
              -- Early eop: switch to PAD to push the partial data down
              -- to symbol 0.
              rv.state := ST_PAD;
              if in_config_c.has_empty then
                rv.pad_eop_empty := (ratio_c - new_filled) * in_spb_c
                                    + empty(in_config_c, in_i);
              else
                rv.pad_eop_empty := (ratio_c - new_filled) * in_spb_c;
              end if;
            end if;
          end if;

        when ST_PAD =>
          -- Keep shifting in zeros until filled saturates, while the
          -- held output slot is free.
          if not is_valid(out_config_c, r.post) or is_ready(out_config_c, out_i) then
            shift_v := true;
            new_filled := r.filled + 1;
            if new_filled = ratio_c then
              do_emit_v := true;
            end if;
          end if;
      end case;

      if shift_v then
        rv.data := in_data_v & r.data(out_dbits_c-1 downto in_dbits_c);
        if out_subits_c /= 0 then
          rv.symbol_user(out_subits_c-1 downto 0)
            := in_suw_v & r.symbol_user(out_subits_c-1 downto in_subits_c);
        end if;
        rv.filled := new_filled mod ratio_c;
      end if;

      if accept_v then
        -- Latch sop on first beat of the group.
        if r.filled = 0 and r.state = ST_FORWARD then
          rv.sop := to_logic(is_sop(in_config_c, in_i, default => false));
        end if;
        -- Latch packet-level fields from the latest accepted beat.
        if cw_c /= 0 then
          rv.channel(cw_c-1 downto 0) := in_i.channel(cw_c-1 downto 0);
        end if;
        if ew_c /= 0 then
          rv.error(ew_c-1 downto 0) := in_i.error(ew_c-1 downto 0);
        end if;
        if puw_c /= 0 then
          rv.packet_user(puw_c-1 downto 0) := in_i.packet_user(puw_c-1 downto 0);
        end if;
      end if;

      if do_emit_v then
        -- Compute the empty count carried out. r.pad_eop_empty was
        -- pre-computed at entry to ST_PAD (regardless of in.has_empty),
        -- and in.empty (read via empty()) returns 0 when in.has_empty
        -- is false, so this expression covers all four corners.
        if r.state = ST_PAD then
          empty_v := r.pad_eop_empty;
        elsif eop_now_v then
          empty_v := empty(in_config_c, in_i);
        else
          empty_v := 0;
        end if;

        -- Build the post beat from rv.data (which already includes
        -- this cycle's shift) and the latched control fields.
        rv.post := transfer_defaults(out_config_c);
        rv.post.valid := '1';
        rv.post.data(out_dbits_c-1 downto 0) := rv.data;
        if out_subits_c /= 0 then
          rv.post.symbol_user(out_subits_c-1 downto 0) := rv.symbol_user(out_subits_c-1 downto 0);
        end if;
        if cw_c /= 0 then
          rv.post.channel(cw_c-1 downto 0) := rv.channel(cw_c-1 downto 0);
        end if;
        if ew_c /= 0 then
          rv.post.error(ew_c-1 downto 0) := rv.error(ew_c-1 downto 0);
        end if;
        if puw_c /= 0 then
          rv.post.packet_user(puw_c-1 downto 0) := rv.packet_user(puw_c-1 downto 0);
        end if;
        if out_config_c.has_packet then
          rv.post.startofpacket := rv.sop;
          if r.state = ST_PAD then
            rv.post.endofpacket := '1';
          else
            rv.post.endofpacket := to_logic(eop_now_v);
          end if;
        end if;
        if out_config_c.has_empty then
          rv.post.empty := to_unsigned(empty_v, empty_t'length);
        end if;

        rv.filled := 0;
        if r.state = ST_PAD then
          rv.state := ST_FORWARD;
        end if;
      end if;

      rin <= rv;
    end process;

    out_o <= r.post;
    in_o  <= accept(in_config_c,
                    r.state = ST_FORWARD
                    and (not is_valid(out_config_c, r.post)
                         or is_ready(out_config_c, out_i)));

  end generate;

  -- Narrowing: in_cfg has more symbols per beat than out_cfg.
  narrow_gen: if in_config_c.symbols_per_beat > out_config_c.symbols_per_beat generate

    constant in_spb_c    : positive := in_config_c.symbols_per_beat;
    constant out_spb_c   : positive := out_config_c.symbols_per_beat;
    constant ratio_c     : positive := in_spb_c / out_spb_c;
    constant in_dbits_c  : positive := in_spb_c  * bps_c;
    constant out_dbits_c : positive := out_spb_c * bps_c;
    constant in_subits_c : natural  := in_spb_c  * suw_c;
    constant out_subits_c: natural  := out_spb_c * suw_c;

    constant zero_out_data_c : std_ulogic_vector(out_dbits_c-1 downto 0) := (others => '0');
    constant zero_out_suw_c  : std_ulogic_vector(nsl_logic.bool.if_else(out_subits_c = 0, 1, out_subits_c)-1 downto 0)
                             := (others => '0');

    type regs_t is record
      valid       : std_ulogic;
      data        : std_ulogic_vector(in_dbits_c-1 downto 0);
      symbol_user : std_ulogic_vector(nsl_logic.bool.if_else(in_subits_c = 0, 1, in_subits_c)-1 downto 0);
      channel     : std_ulogic_vector(nsl_logic.bool.if_else(cw_c = 0, 1, cw_c)-1 downto 0);
      error       : std_ulogic_vector(nsl_logic.bool.if_else(ew_c = 0, 1, ew_c)-1 downto 0);
      packet_user : std_ulogic_vector(nsl_logic.bool.if_else(puw_c = 0, 1, puw_c)-1 downto 0);
      sop         : std_ulogic;
      eop         : std_ulogic;
      emits_left  : natural range 0 to ratio_c;
      last_empty  : natural range 0 to out_spb_c;
    end record;

    signal r, rin : regs_t;

    function emits_for(valid_symbols: natural) return natural is
    begin
      if valid_symbols = 0 then
        return 1;
      else
        return (valid_symbols + out_spb_c - 1) / out_spb_c;
      end if;
    end function;

  begin

    reg: process(clock_i, reset_n_i) is
    begin
      if reset_n_i = '0' then
        r.valid      <= '0';
        r.emits_left <= 0;
      elsif rising_edge(clock_i) then
        r <= rin;
      end if;
    end process;

    cb: process(r, in_i, out_i) is
      variable rv     : regs_t;
      variable take_in_v   : boolean;
      variable advance_v   : boolean;
      variable valid_in_v  : natural;
      variable emits_v     : natural;
    begin
      rv := r;

      -- An output beat is emitted whenever the sink is ready AND we
      -- have a valid wide beat to drain.
      advance_v := r.valid = '1' and is_ready(out_config_c, out_i);

      if advance_v then
        rv.data := zero_out_data_c & r.data(in_dbits_c-1 downto out_dbits_c);
        if in_subits_c /= 0 then
          rv.symbol_user(in_subits_c-1 downto 0)
            := zero_out_suw_c & r.symbol_user(in_subits_c-1 downto out_subits_c);
        end if;
        rv.emits_left := r.emits_left - 1;
        rv.sop := '0';
        if r.emits_left = 1 then
          rv.valid := '0';
          rv.eop   := '0';
        end if;
      end if;

      -- Accept a new wide beat when the current one will be empty after
      -- this cycle (either we're idle, or we're about to finish).
      take_in_v := is_valid(in_config_c, in_i)
                   and (r.valid = '0' or (advance_v and r.emits_left = 1));

      if take_in_v then
        if in_config_c.has_empty and is_eop(in_config_c, in_i, default => false) then
          valid_in_v := in_spb_c - empty(in_config_c, in_i);
        else
          valid_in_v := in_spb_c;
        end if;
        emits_v := emits_for(valid_in_v);

        rv.valid := '1';
        rv.data(in_dbits_c-1 downto 0) := in_i.data(in_dbits_c-1 downto 0);
        if in_subits_c /= 0 then
          rv.symbol_user(in_subits_c-1 downto 0) := in_i.symbol_user(in_subits_c-1 downto 0);
        end if;
        if cw_c /= 0 then
          rv.channel(cw_c-1 downto 0) := in_i.channel(cw_c-1 downto 0);
        end if;
        if ew_c /= 0 then
          rv.error(ew_c-1 downto 0) := in_i.error(ew_c-1 downto 0);
        end if;
        if puw_c /= 0 then
          rv.packet_user(puw_c-1 downto 0) := in_i.packet_user(puw_c-1 downto 0);
        end if;
        rv.sop := to_logic(is_sop(in_config_c, in_i, default => false));
        rv.eop := to_logic(is_eop(in_config_c, in_i, default => false));
        rv.emits_left := emits_v;
        rv.last_empty := emits_v * out_spb_c - valid_in_v;
      end if;

      rin <= rv;
    end process;

    drv: process(r) is
      variable beat : source_t;
      variable is_last : boolean;
    begin
      beat := transfer_defaults(out_config_c);
      beat.data(out_dbits_c-1 downto 0) := r.data(out_dbits_c-1 downto 0);
      if out_subits_c /= 0 then
        beat.symbol_user(out_subits_c-1 downto 0) := r.symbol_user(out_subits_c-1 downto 0);
      end if;
      if cw_c /= 0 then
        beat.channel(cw_c-1 downto 0) := r.channel(cw_c-1 downto 0);
      end if;
      if ew_c /= 0 then
        beat.error(ew_c-1 downto 0) := r.error(ew_c-1 downto 0);
      end if;
      if puw_c /= 0 then
        beat.packet_user(puw_c-1 downto 0) := r.packet_user(puw_c-1 downto 0);
      end if;

      is_last := r.emits_left = 1;

      if out_config_c.has_packet then
        beat.startofpacket := r.sop;
        if is_last then
          beat.endofpacket := r.eop;
        else
          beat.endofpacket := '0';
        end if;
      end if;

      if out_config_c.has_empty then
        if is_last then
          beat.empty := to_unsigned(r.last_empty, empty_t'length);
        else
          beat.empty := (others => '0');
        end if;
      end if;

      beat.valid := r.valid;

      out_o <= beat;
    end process;

    in_o <= accept(in_config_c, r.valid = '0' or (is_ready(out_config_c, out_i) and r.emits_left = 1));

  end generate;

end architecture;
