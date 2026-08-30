library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

package checksum is

  subtype checksum_field_t is byte_string(0 to 1);

  -- Byte-serial accumulator.
  --
  -- This is the compatibility surface: it is a thin re-typing of the
  -- parametric accumulator below at a one-byte chunk, kept for the
  -- code and the external users written against it.  New code takes
  -- the parametric family, which folds a whole beat per update.
  subtype checksum_acc_t is signed(16 downto 0);

  constant checksum_acc_init_c : checksum_acc_t := "01111111111111111";

  function checksum_update(acc: checksum_acc_t; d: byte)
    return checksum_acc_t;

  function checksum_update(acc: checksum_acc_t; s: byte_string)
    return checksum_acc_t;

  -- Tells whether the accumulated data carries a correct internet
  -- checksum, i.e. whether the one's complement sum of the 16-bit
  -- words folded so far is zero (either encoding of the one's
  -- complement zero).
  --
  -- The accumulator holds a one's complement value spread over a
  -- 16-bit residue acc(15 downto 0) and a pending borrow acc(16), the
  -- value being acc(15 downto 0) - acc(16) modulo 65535.  Update
  -- flavors leave the same value in different encodings, so the
  -- decision is taken on the normalized value.
  function checksum_acc_is_valid(acc: checksum_acc_t) return boolean;

  function checksum_is_valid(data : byte_string) return boolean;

  function checksum_spill(acc: checksum_acc_t;
                          is_misaligned: boolean := false)
    return checksum_field_t;

  -- Parametric accumulator.
  --
  -- Configuration and state are records, as in nsl_data.crc: the
  -- widest chunk the package handles is a constant that can be
  -- enlarged ad libitum, a state carries a maximum-sized accumulator,
  -- and the bits a given configuration leaves unused are constant,
  -- hence optimized out.
  --
  -- This accumulator holds the very value the byte-serial one above
  -- holds, in the very same direction: the complement of the one's
  -- complement sum of the 16-bit words covered so far, i.e. what a
  -- checksum field of these words has to carry.  Every update is a
  -- single subtract-with-borrow, that is one adder taking the
  -- complement of the term and a carry input, whatever the count of
  -- bytes the update takes at once.
  --
  -- The accumulator is a residue of 16*n bits and a pending borrow
  -- just above it.  2**(16*n) is congruent to 1 modulo 65535, so the
  -- residue stands for the sum of its 16-bit words and the borrow is
  -- worth minus one.  A chunk is therefore folded in at the low end
  -- of the residue whatever its size, as long as it is a whole count
  -- of 16-bit words starting on a 16-bit boundary of the covered
  -- data.
  --
  -- Widest chunk a configuration may take.  Sizing the state for
  -- eight bytes leaves room for a 64-bit stream.
  constant checksum_max_chunk_c: natural := 8;
  constant checksum_max_residue_c: natural := 8 * checksum_max_chunk_c;

  subtype checksum_value_t is unsigned(15 downto 0);

  type checksum_config_t is
  record
    -- Count of bytes folded into the accumulator per update.  Even
    -- chunks are a whole count of 16-bit words.  The one-byte chunk
    -- serves the odd stream widths, its parity being handled by
    -- rotating the residue, which is what the byte-serial update does
    -- expressed as an addition.
    chunk_bytes: natural;
    -- Bits of the accumulator residue: a whole count of 16-bit words,
    -- wide enough to take a chunk.
    residue_bits: natural;
  end record;

  type checksum_state_t is
  record
    -- Residue in the low residue_bits bits, pending borrow just
    -- above, zeroes over it.  Refrain from dereferencing this field
    -- directly from code.
    value: unsigned(checksum_max_residue_c downto 0);
  end record;

  -- Configuration folding chunk_bytes bytes per update.  Chunk must
  -- be even, one byte being the only odd chunk the engine supports.
  function checksum_config(chunk_bytes: natural) return checksum_config_t;

  -- Configuration folding one whole beat of a stream per update.
  -- Even stream widths take the whole beat as a chunk; a one-byte
  -- stream takes the byte chunk.
  function checksum_config(stream_config: nsl_amba.axi4_stream.config_t)
    return checksum_config_t;

  -- Configuration folding one byte per update, which the byte-serial
  -- accumulator above is a re-typing of.  This is the configuration
  -- of the bnoc stack, whose layers carry one byte per cycle.
  constant checksum_byte_config_c: checksum_config_t;

  -- Accumulator covering nothing yet.
  function checksum_init(cfg: checksum_config_t) return checksum_state_t;

  -- Accumulator covering what a byte-serial accumulator covers.  This
  -- is the bridge between the two families, and it is pure wiring: the
  -- residue words the seed does not reach are left all ones, which
  -- stand for zero.
  function checksum_seed(cfg: checksum_config_t;
                         acc: checksum_acc_t) return checksum_state_t;

  -- Accumulates a byte string taken big endian, by chunks.  The
  -- string must be a whole count of 16-bit words starting on a 16-bit
  -- boundary of the covered data; a trailing odd byte is taken as the
  -- high half of a zero-padded word, so it must end the covered data.
  --
  -- A byte chunk rotates the accumulator rather than padding, which
  -- leaves the value scaled by 256 after an odd count of bytes.  That
  -- scaling is invisible to checksum_is_valid, it matters to the
  -- other finalizations.
  function checksum_update(cfg: checksum_config_t;
                           state: checksum_state_t;
                           data: byte_string) return checksum_state_t;

  -- Accumulates the kept prefix of an AXI4-Stream beat, one beat per
  -- update.  Beats are expected to be packed; unkept bytes of an even
  -- chunk are masked to zero, the additive identity, so a partial
  -- beat zero-pads to a whole count of 16-bit words and must be the
  -- last of its packet.
  function checksum_update(cfg: checksum_config_t;
                           state: checksum_state_t;
                           stream_config: nsl_amba.axi4_stream.config_t;
                           beat: nsl_amba.axi4_stream.master_t)
    return checksum_state_t;

  -- Accumulated value, reduced to the 16 bits a checksum field
  -- carries: the complement of the one's complement sum of the
  -- covered words.  As the byte-serial accumulator does, this yields
  -- the 16#ffff# encoding of the one's complement zero for all-zero
  -- data only, the 0 encoding for anything else summing to zero.
  function checksum_finalize(cfg: checksum_config_t;
                             state: checksum_state_t)
    return checksum_value_t;

  -- Tells whether the accumulated data carries a correct internet
  -- checksum.
  --
  -- This is why the accumulator counts down: a receiver folding a
  -- packet and the checksum field covering it finalizes to the one's
  -- complement zero, whose principal encoding is the all-zeroes
  -- pattern, where accumulating the plain sum would leave the
  -- all-ones one.  Comparing an accumulator to zero is the pattern
  -- detection a DSP block hands over for free.  The other encoding of
  -- the one's complement zero, unavoidable in that arithmetic, is
  -- accepted too, as are the encodings an unreduced residue wider
  -- than one word leaves.
  function checksum_is_valid(cfg: checksum_config_t;
                             state: checksum_state_t) return boolean;

  -- Finalizes the accumulator into the two-byte field to store in a
  -- header.  For the same covered data, the byte-serial spill above
  -- yields these very bytes.
  function checksum_spill(cfg: checksum_config_t;
                          state: checksum_state_t) return checksum_field_t;

  -- Pass-through stream component verifying the internet checksum of
  -- every packet that traverses it.  Bytes covered by the checksum
  -- are accumulated from init_i, sampled at the first beat of each
  -- packet; a packet whose accumulated checksum does not verify gets
  -- the reject flag (user bit 0) set on its last beat.  An already
  -- set reject flag is propagated regardless of the verdict.
  --
  -- For checksums covering a pseudo-header (UDP, TCP), init_i is the
  -- accumulator value after folding the pseudo-header contents.
  --
  -- Stream configuration must have last and at least one user bit.
  component checksum_stream_validator is
    generic(
      config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      init_i : in checksum_state_t
        := checksum_init(checksum_config(config_c));

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package;

package body checksum is

  function checksum_config(chunk_bytes: natural)
    return checksum_config_t
  is
    variable ret: checksum_config_t;
  begin
    assert chunk_bytes = 1 or chunk_bytes mod 2 = 0
      report "Only the one-byte chunk may hold an odd count of bytes"
      severity failure;
    assert 1 <= chunk_bytes and chunk_bytes <= checksum_max_chunk_c
      report "Chunk is wider than the state this package carries"
      severity failure;

    ret.chunk_bytes := chunk_bytes;
    if chunk_bytes <= 2 then
      ret.residue_bits := 16;
    else
      ret.residue_bits := 8 * chunk_bytes;
    end if;

    return ret;
  end function;

  function checksum_config(stream_config: nsl_amba.axi4_stream.config_t)
    return checksum_config_t
  is
  begin
    assert stream_config.data_width mod 2 = 0
      or stream_config.data_width = 1
      report "Odd stream widths above one byte carry no whole count of"
      &" 16-bit words per beat"
      severity failure;

    return checksum_config(stream_config.data_width);
  end function;

  constant checksum_byte_config_c: checksum_config_t := checksum_config(1);

  function checksum_init(cfg: checksum_config_t)
    return checksum_state_t
  is
    variable ret: checksum_state_t;
  begin
    -- An all-ones residue is a whole count of all-ones words, the
    -- complement of a null sum.
    ret.value := (others => '0');
    ret.value(cfg.residue_bits-1 downto 0) := (others => '1');

    return ret;
  end function;

  function checksum_seed(cfg: checksum_config_t;
                         acc: checksum_acc_t)
    return checksum_state_t
  is
    variable ret: checksum_state_t := checksum_init(cfg);
  begin
    ret.value(15 downto 0) := unsigned(acc(15 downto 0));
    ret.value(cfg.residue_bits) := acc(16);

    return ret;
  end function;

  -- One update step: the residue minus the term the chunk stands for,
  -- minus the borrow the previous step left.  This is one adder
  -- taking the complement of the term and a carry input; bit
  -- residue_bits of the outcome is the borrow the next step takes
  -- back in.
  function checksum_chunk(cfg: checksum_config_t;
                          state: checksum_state_t;
                          chunk: byte_string)
    return checksum_state_t
  is
    constant top_c: natural := cfg.residue_bits;
    variable a, t, r: unsigned(top_c downto 0);
    variable c: unsigned(0 downto 0);
    variable ret: checksum_state_t;
  begin
    if cfg.chunk_bytes mod 2 = 0 then
      assert chunk'length mod 2 = 0 and chunk'length <= cfg.chunk_bytes
        report "Chunk must be a whole count of 16-bit words, at most a"
        &" configured chunk wide"
        severity failure;

      a := "0" & state.value(top_c-1 downto 0);
      t := "0" & resize(from_be(chunk), top_c);
      c(0) := not state.value(top_c);
    else
      assert chunk'length = 1
        report "A byte chunk takes one byte"
        severity failure;

      -- A byte chunk covers one half of a 16-bit word, the other half
      -- being covered by the neighbouring chunks.  Scaling the
      -- accumulated value by 256 before every byte alternates the
      -- halves: this is a rotation of the one-word residue, the
      -- pending borrow following it up to bit 8 where it joins the
      -- term.
      a := "0" & state.value(7 downto 0) & state.value(15 downto 8);
      t := "00000000" & state.value(top_c) & unsigned(chunk(chunk'left));
      c(0) := '1';
    end if;

    r := a + (not t) + c;

    ret.value := (others => '0');
    ret.value(top_c downto 0) := r;

    return ret;
  end function;

  function checksum_update(cfg: checksum_config_t;
                           state: checksum_state_t;
                           data: byte_string)
    return checksum_state_t
  is
    alias d: byte_string(0 to data'length-1) is data;
    constant word_count_c: natural := (data'length + 1) / 2;
    constant chunk_words_c: natural := (cfg.chunk_bytes + 1) / 2;
    variable padded: byte_string(0 to 2*word_count_c-1) := (others => x"00");
    variable ret: checksum_state_t := state;
    variable index, take: natural;
  begin
    if cfg.chunk_bytes mod 2 = 1 then
      for i in d'range
      loop
        ret := checksum_chunk(cfg, ret, d(i to i));
      end loop;

      return ret;
    end if;

    padded(0 to data'length-1) := d;

    index := 0;
    while index < word_count_c
    loop
      take := word_count_c - index;
      if take > chunk_words_c then
        take := chunk_words_c;
      end if;

      ret := checksum_chunk(cfg, ret, padded(2*index to 2*(index+take)-1));
      index := index + take;
    end loop;

    return ret;
  end function;

  function checksum_update(cfg: checksum_config_t;
                           state: checksum_state_t;
                           stream_config: nsl_amba.axi4_stream.config_t;
                           beat: nsl_amba.axi4_stream.master_t)
    return checksum_state_t
  is
    constant d: byte_string(0 to stream_config.data_width-1)
      := nsl_amba.axi4_stream.bytes(stream_config, beat);
    constant k: std_ulogic_vector(0 to stream_config.data_width-1)
      := nsl_amba.axi4_stream.keep(stream_config, beat);
    variable masked: byte_string(0 to stream_config.data_width-1);
  begin
    assert cfg.chunk_bytes = stream_config.data_width
      report "Configuration does not match the stream width"
      severity failure;

    for i in d'range
    loop
      if k(i) = '1' then
        masked(i) := d(i);
      else
        masked(i) := x"00";
      end if;
    end loop;

    -- Zero is the additive identity, an unkept byte of an even chunk
    -- is folded in as it comes.  A byte chunk rotates, so an unkept
    -- byte has to leave the accumulator untouched instead.
    if cfg.chunk_bytes mod 2 = 1 and k(0) /= '1' then
      return state;
    end if;

    return checksum_chunk(cfg, state, masked);
  end function;

  -- Bits the unreduced sum of the residue words and of the pending
  -- borrow takes: a word, the carry a word sum leaves, and one bit
  -- more per doubling of the word count.
  function checksum_sum_bits(cfg: checksum_config_t)
    return natural
  is
    variable words, ret: natural;
  begin
    words := cfg.residue_bits / 16;
    ret := 17;
    while words > 1
    loop
      words := (words + 1) / 2;
      ret := ret + 1;
    end loop;

    return ret;
  end function;

  -- One's complement sum of the words covered so far, congruent to it
  -- modulo 65535 rather than reduced to 16 bits.
  --
  -- The complement of the residue is that sum: an all-ones residue is
  -- a whole count of all-ones words, congruent to zero, and
  -- complementing negates modulo 65535.  The pending borrow joins the
  -- sum as a plain carry for the same reason, so it rides the adder's
  -- carry input rather than an addition of its own.
  function checksum_sum(cfg: checksum_config_t;
                        state: checksum_state_t)
    return unsigned
  is
    constant words_c: natural := cfg.residue_bits / 16;
    constant len_c: natural := checksum_sum_bits(cfg);
    constant comp_c: unsigned(cfg.residue_bits-1 downto 0)
      := not state.value(cfg.residue_bits-1 downto 0);
    variable carry_v: unsigned(0 downto 0);
    variable acc_v: unsigned(len_c-1 downto 0);
  begin
    carry_v(0) := state.value(cfg.residue_bits);

    if words_c = 1 then
      acc_v := resize(comp_c(15 downto 0), len_c) + carry_v;
    else
      acc_v := resize(comp_c(15 downto 0), len_c)
               + comp_c(31 downto 16) + carry_v;

      for i in 2 to words_c-1
      loop
        acc_v := acc_v + comp_c(16*i+15 downto 16*i);
      end loop;
    end if;

    return acc_v;
  end function;

  function checksum_finalize(cfg: checksum_config_t;
                             state: checksum_state_t)
    return checksum_value_t
  is
    constant len_c: natural := checksum_sum_bits(cfg);
    constant sum_c: unsigned(len_c-1 downto 0) := checksum_sum(cfg, state);
    -- One end-around carry brings the sum within one of the 16 bits it
    -- must fit in, whatever the count of words: what folds back is the
    -- handful of bits the word sum carried over, and adding them can
    -- carry once more, never twice.  Both outcomes are computed side
    -- by side and the carry picks between them, which keeps the
    -- reduction one adder deep where rounds of folding would take one
    -- per bit of overflow.
    constant folded_c: unsigned(16 downto 0)
      := resize(sum_c(15 downto 0), 17) + sum_c(len_c-1 downto 16);
    constant carried_c: unsigned(16 downto 0)
      := resize(sum_c(15 downto 0), 17) + sum_c(len_c-1 downto 16) + 1;
  begin
    -- Complementing leaves the usual encoding: a sum of zero comes
    -- from all-zero data only and yields 16#ffff#, while anything else
    -- summing to zero holds the 16#ffff# encoding and yields zero.
    if folded_c(16) = '1' then
      return not carried_c(15 downto 0);
    end if;

    return not folded_c(15 downto 0);
  end function;

  function checksum_is_valid(cfg: checksum_config_t;
                             state: checksum_state_t)
    return boolean
  is
    constant sum_c: unsigned := checksum_sum(cfg, state);
    variable ret: boolean := false;
  begin
    -- The sum is left unreduced, so every multiple of 65535 it can
    -- reach encodes the one's complement zero.
    for i in 0 to cfg.residue_bits / 16
    loop
      if sum_c = 65535 * i then
        ret := true;
      end if;
    end loop;

    return ret;
  end function;

  function checksum_spill(cfg: checksum_config_t;
                          state: checksum_state_t)
    return checksum_field_t
  is
  begin
    return to_be(checksum_finalize(cfg, state));
  end function;

  -- The byte-serial accumulator is the state of the parametric one at
  -- a one-byte chunk seen through another type: sixteen bits of
  -- residue and the pending borrow just above them, in both.  The two
  -- re-typings below are pure bit copies, and every function of the
  -- byte-serial family is the matching parametric one taken between
  -- them.
  function to_state(acc: checksum_acc_t)
    return checksum_state_t
  is
  begin
    return checksum_seed(checksum_byte_config_c, acc);
  end function;

  function to_acc(state: checksum_state_t)
    return checksum_acc_t
  is
  begin
    return signed(state.value(checksum_byte_config_c.residue_bits downto 0));
  end function;

  function checksum_update(acc: checksum_acc_t; d: byte)
    return checksum_acc_t
  is
  begin
    return to_acc(checksum_update(checksum_byte_config_c, to_state(acc),
                                  byte_string'(0 => d)));
  end function;

  function checksum_update(acc: checksum_acc_t; s: byte_string)
    return checksum_acc_t
  is
  begin
    return to_acc(checksum_update(checksum_byte_config_c, to_state(acc), s));
  end function;

  function checksum_acc_is_valid(acc: checksum_acc_t)
    return boolean
  is
  begin
    return checksum_is_valid(checksum_byte_config_c, to_state(acc));
  end function;

  function checksum_is_valid(data : byte_string)
    return boolean
  is
  begin
    return checksum_acc_is_valid(checksum_update(checksum_acc_init_c,
                                                 data & x"00"));
  end function;

  function checksum_spill(acc: checksum_acc_t;
                          is_misaligned: boolean := false)
    return checksum_field_t
  is
    variable state: checksum_state_t := to_state(acc);
  begin
    -- An odd count of covered bytes leaves the accumulated value
    -- scaled by 256, the byte chunk rotating the residue.  Folding one
    -- zero byte in takes that scaling back without touching the value.
    if is_misaligned then
      state := checksum_update(checksum_byte_config_c, state,
                               byte_string'(0 => x"00"));
    end if;

    return checksum_spill(checksum_byte_config_c, state);
  end function;

end package body;
