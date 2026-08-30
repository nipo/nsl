library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;
use nsl_inet.checksum.all;

entity tb is
end tb;

architecture arch of tb is

  constant trial_count_c: integer := 3000;
  constant max_length_c: integer := 80;

  -- One's complement sum of the 16-bit big endian words of data, tail
  -- byte zero-padded, as defined by RFC 1071.  Plain integer
  -- arithmetic with an end-around carry, sharing no code with the
  -- accumulator under test.
  function reference_sum(data: byte_string)
    return integer
  is
    variable sum, word, index: integer;
  begin
    sum := 0;
    index := data'low;
    while index <= data'high
    loop
      word := to_integer(unsigned(data(index))) * 256;
      if index < data'high then
        word := word + to_integer(unsigned(data(index+1)));
      end if;
      sum := sum + word;
      if sum > 65535 then
        sum := sum - 65535;
      end if;
      index := index + 2;
    end loop;
    return sum;
  end function;

  -- A checksummed byte string verifies when the one's complement sum
  -- of its words is zero.  Zero has two encodings in one's complement
  -- arithmetic: 16#ffff# is the usual one, 0 only comes out of an
  -- all-zero string.
  function reference_is_valid(data: byte_string)
    return boolean
  is
    constant sum: integer := reference_sum(data);
  begin
    return sum = 65535 or sum = 0;
  end function;

  function fold_serial(data: byte_string;
                       seed: checksum_acc_t := checksum_acc_init_c)
    return checksum_acc_t
  is
    variable acc: checksum_acc_t := seed;
  begin
    for index in data'range
    loop
      acc := checksum_update(acc, data(index));
    end loop;
    return acc;
  end function;

  -- Hands the data over by 16-bit words, a trailing odd byte going
  -- through the byte overload.  However the string is cut up, the
  -- byte_string overload must leave the very same accumulator the
  -- byte-by-byte fold leaves.
  function fold_word(data: byte_string)
    return checksum_acc_t
  is
    variable acc: checksum_acc_t := checksum_acc_init_c;
    variable index: integer;
  begin
    index := data'low;
    while index <= data'high
    loop
      if index < data'high then
        acc := checksum_update(acc, data(index to index+1));
        index := index + 2;
      else
        acc := checksum_update(acc, data(index));
        index := index + 1;
      end if;
    end loop;
    return acc;
  end function;

  -- Hands the data over by chunks of 1 to 8 bytes taken from sizes,
  -- which reaches the byte_string overload at either alignment.
  function fold_chunked(data, sizes: byte_string)
    return checksum_acc_t
  is
    variable acc: checksum_acc_t := checksum_acc_init_c;
    variable index, size, cursor: integer;
  begin
    index := 0;
    cursor := data'low;
    while cursor <= data'high
    loop
      size := 1 + (to_integer(unsigned(sizes(sizes'low + (index mod sizes'length)))) mod 8);
      if cursor + size - 1 > data'high then
        size := data'high - cursor + 1;
      end if;
      acc := checksum_update(acc, data(cursor to cursor + size - 1));
      cursor := cursor + size;
      index := index + 1;
    end loop;
    return acc;
  end function;

  function stream_cfg(width: integer)
    return config_t
  is
  begin
    return config(bytes => width, keep => true, last => true);
  end function;

  -- Folds through the parametric accumulator, one beat per update,
  -- packed, only the last beat being partial.  The accumulator starts
  -- from the value seed stands for.
  function fold_parametric(data: byte_string;
                           width: integer;
                           seed: checksum_acc_t := checksum_acc_init_c)
    return checksum_state_t
  is
    constant scfg: config_t := stream_cfg(width);
    constant cfg: checksum_config_t := checksum_config(scfg);
    variable state: checksum_state_t := checksum_seed(cfg, seed);
    variable beat_data: byte_string(0 to width-1);
    variable beat_keep: std_ulogic_vector(0 to width-1);
    variable cursor, size: integer;
  begin
    cursor := data'low;
    while cursor <= data'high
    loop
      size := width;
      if cursor + size - 1 > data'high then
        size := data'high - cursor + 1;
      end if;

      -- Bytes above the kept prefix are left with whatever the
      -- previous beat carried, the accumulator has to mask them out.
      beat_keep := (others => '0');
      beat_data(0 to size-1) := data(cursor to cursor + size - 1);
      beat_keep(0 to size-1) := (others => '1');

      state := checksum_update(cfg, state, scfg,
                               transfer(scfg,
                                        bytes => beat_data,
                                        keep => beat_keep,
                                        last => cursor + size > data'high));
      cursor := cursor + size;
    end loop;
    return state;
  end function;

  -- Folds through the parametric accumulator by byte strings, in
  -- pieces of an even count of bytes taken from sizes so that every
  -- call but the last starts on a 16-bit boundary.  Pieces run from
  -- two to eight bytes, so the narrower chunks get pieces wider than
  -- themselves and the chunking of the byte string overload is
  -- exercised as well.
  function fold_pieces(data, sizes: byte_string;
                       chunk: integer;
                       seed: checksum_acc_t := checksum_acc_init_c)
    return checksum_state_t
  is
    constant cfg: checksum_config_t := checksum_config(chunk);
    variable state: checksum_state_t := checksum_seed(cfg, seed);
    variable index, size, cursor: integer;
  begin
    index := 0;
    cursor := data'low;
    while cursor <= data'high
    loop
      size := 2 * (1 + (to_integer(unsigned(sizes(sizes'low
                                                  + (index mod sizes'length))))
                        mod 4));
      if cursor + size - 1 > data'high then
        size := data'high - cursor + 1;
      end if;
      state := checksum_update(cfg, state, data(cursor to cursor + size - 1));
      cursor := cursor + size;
      index := index + 1;
    end loop;
    return state;
  end function;

  -- Every fold path must reach the same verdict as the reference, and
  -- the aligned spill, which only depends on the accumulated value,
  -- must give the same bytes whatever the path.  The reference model
  -- is what carries the proof: the byte-serial accumulator is the
  -- parametric one at a one-byte chunk seen through another type, so
  -- the comparisons against it only tell that re-typing apart.
  procedure check_paths(what: in string;
                        data: in byte_string;
                        sizes: in byte_string)
  is
    constant expected: boolean := reference_is_valid(data);
    constant serial_acc: checksum_acc_t := fold_serial(data);
    constant misaligned: boolean := data'length mod 2 = 1;
    variable cfg_v: checksum_config_t;
    variable state_v: checksum_state_t;
    variable size_v: integer;
  begin
    assert_equal(what & " byte-serial fold",
                 checksum_acc_is_valid(serial_acc), expected, failure);
    assert_equal(what & " 16-bit fold",
                 checksum_acc_is_valid(fold_word(data)), expected, failure);
    assert_equal(what & " chunked fold",
                 checksum_acc_is_valid(fold_chunked(data, sizes)), expected, failure);

    assert_equal(what & " 16-bit fold spill",
                 checksum_spill(fold_word(data)),
                 checksum_spill(serial_acc), failure);
    assert_equal(what & " chunked fold spill",
                 checksum_spill(fold_chunked(data, sizes)),
                 checksum_spill(serial_acc), failure);

    -- Parametric accumulator, one beat per update.  It holds the very
    -- value the byte-serial accumulator holds, so it must reach the
    -- reference verdict and spill the very same field.
    --
    -- An even chunk zero-pads a trailing odd byte, which leaves the
    -- accumulator on the 16-bit boundaries of the covered data, where
    -- the byte chunk rotates and leaves the value scaled by 256 after
    -- an odd count of bytes.  That is exactly the scaling the
    -- misaligned byte-serial spill undoes.
    for wl2 in 0 to 2
    loop
      size_v := 2 ** wl2;
      cfg_v := checksum_config(stream_cfg(size_v));
      state_v := fold_parametric(data, size_v);

      assert_equal(what & " parametric beat fold, width " & to_string(size_v),
                   checksum_is_valid(cfg_v, state_v), expected, failure);
      assert_equal(what & " parametric beat spill, width " & to_string(size_v),
                   checksum_spill(cfg_v, state_v),
                   checksum_spill(serial_acc,
                                  is_misaligned => misaligned and size_v > 1),
                   failure);
      if size_v mod 2 = 0 or not misaligned then
        assert_equal(what & " parametric beat value, width " & to_string(size_v),
                     to_integer(checksum_finalize(cfg_v, state_v)),
                     65535 - reference_sum(data), failure);
      end if;
    end loop;

    -- Same accumulator fed by byte strings, at every chunk the
    -- package handles.
    for cl2 in 1 to 3
    loop
      size_v := 2 ** cl2;
      cfg_v := checksum_config(size_v);
      state_v := fold_pieces(data, sizes, size_v);

      assert_equal(what & " parametric chunked fold, chunk " & to_string(size_v),
                   checksum_is_valid(cfg_v, state_v), expected, failure);
      assert_equal(what & " parametric chunked value, chunk " & to_string(size_v),
                   to_integer(checksum_finalize(cfg_v, state_v)),
                   65535 - reference_sum(data), failure);
      assert_equal(what & " parametric chunked spill, chunk " & to_string(size_v),
                   checksum_spill(cfg_v, state_v),
                   checksum_spill(serial_acc, is_misaligned => misaligned),
                   failure);
    end loop;
  end procedure;

  -- checksum_seed must carry over the very value the byte-serial
  -- accumulator stands for, whatever encoding it carries, so that a
  -- pseudo-header folded byte by byte and a datagram folded by chunks
  -- share one accumulator.
  procedure check_seed(what: in string;
                       seed: in checksum_acc_t;
                       chunk: in integer)
  is
    constant cfg: checksum_config_t := checksum_config(chunk);
    constant state: checksum_state_t := checksum_seed(cfg, seed);
  begin
    assert_equal(what & " seed spill, chunk " & to_string(chunk),
                 checksum_spill(cfg, state),
                 checksum_spill(seed), failure);
    assert_equal(what & " seed verdict, chunk " & to_string(chunk),
                 checksum_is_valid(cfg, state),
                 checksum_acc_is_valid(seed), failure);
  end procedure;

  procedure check_seed_all(what: in string;
                           seed: in checksum_acc_t)
  is
  begin
    check_seed(what, seed, 1);
    check_seed(what, seed, 2);
    check_seed(what, seed, 4);
    check_seed(what, seed, 8);
  end procedure;

  -- Folding data on top of a pseudo-header accumulator must reach the
  -- same verdict, and the same value, as folding the concatenation.
  -- The pseudo-header must be an even count of bytes for the
  -- concatenation to keep the 16-bit boundaries of both parts.
  procedure check_seeded(what: in string;
                         pseudo: in byte_string;
                         data: in byte_string;
                         sizes: in byte_string)
  is
    constant seed: checksum_acc_t := fold_serial(pseudo);
    constant whole: byte_string(0 to pseudo'length + data'length - 1)
      := pseudo & data;
    constant expected: boolean := reference_is_valid(whole);
    constant misaligned: boolean := data'length mod 2 = 1;
    variable cfg_v: checksum_config_t;
    variable state_v: checksum_state_t;
    variable size_v: integer;
  begin
    check_seed_all(what, seed);

    for wl2 in 0 to 2
    loop
      size_v := 2 ** wl2;
      cfg_v := checksum_config(stream_cfg(size_v));
      state_v := fold_parametric(data, size_v, seed);

      assert_equal(what & " seeded beat fold, width " & to_string(size_v),
                   checksum_is_valid(cfg_v, state_v), expected, failure);
      -- The byte chunk of the one-byte stream walks the very steps
      -- the byte-serial accumulator walks, seed included.
      assert_equal(what & " seeded beat spill, width " & to_string(size_v),
                   checksum_spill(cfg_v, state_v),
                   checksum_spill(fold_serial(data, seed),
                                  is_misaligned => misaligned and size_v > 1),
                   failure);
      if size_v mod 2 = 0 or not misaligned then
        assert_equal(what & " seeded beat value, width " & to_string(size_v),
                     to_integer(checksum_finalize(cfg_v, state_v)),
                     65535 - reference_sum(whole), failure);
      end if;
    end loop;

    for cl2 in 1 to 3
    loop
      size_v := 2 ** cl2;
      cfg_v := checksum_config(size_v);
      state_v := fold_pieces(data, sizes, size_v, seed);

      assert_equal(what & " seeded chunked fold, chunk " & to_string(size_v),
                   checksum_is_valid(cfg_v, state_v), expected, failure);
      assert_equal(what & " seeded chunked value, chunk " & to_string(size_v),
                   to_integer(checksum_finalize(cfg_v, state_v)),
                   65535 - reference_sum(whole), failure);
    end loop;
  end procedure;

begin

  checker: process is
    variable prbs_v: prbs_state(30 downto 0) := x"c0ffee1"&"011";
    variable random_v: byte_string(0 to max_length_c + 8);
    variable data_v: byte_string(0 to max_length_c + 1);
    variable len_v, split_v, valid_count_v: integer;
    variable field_v, par_field_v: checksum_field_t;
  begin
    -- Directed vectors for the accumulator encodings that carry the
    -- one's complement zero.  However the string is handed over, the
    -- byte-serial accumulator walks the same steps and lands on the
    -- same encoding, all zeroes here.
    check_paths("all-ones tail word", from_hex("ffffffff"), from_hex("01020304"));
    assert_equal("all-ones tail word, 16-bit fold encoding",
                 std_ulogic_vector(fold_word(from_hex("ffffffff"))),
                 std_ulogic_vector(fold_serial(from_hex("ffffffff"))), failure);
    assert_equal("all-ones tail word, byte-serial fold encoding",
                 std_ulogic_vector(fold_serial(from_hex("ffffffff"))),
                 std_ulogic_vector'("0" & x"0000"), failure);

    check_paths("all-ones tail word, long",
                from_hex("1234edcb0000ffffffff"), from_hex("02030405"));
    check_paths("all-ones tail word, odd length",
                from_hex("1234edcbff00ffffffff30"), from_hex("03040506"));

    -- A sum of one leaves minus one in the accumulator, encoded as
    -- all ones by both folds.  That is not the one's complement zero.
    check_paths("sum of one", from_hex("0002fffe"), from_hex("01020304"));
    assert_equal("sum of one, byte-serial fold encoding",
                 std_ulogic_vector(fold_serial(from_hex("0002fffe"))),
                 std_ulogic_vector'("1" & x"ffff"), failure);
    assert_equal("sum of one, 16-bit fold encoding",
                 std_ulogic_vector(fold_word(from_hex("0002fffe"))),
                 std_ulogic_vector'("1" & x"ffff"), failure);

    -- An all-zero string sums to plus zero, the accumulator holds the
    -- init value.
    check_paths("all zeroes", from_hex("0000"), from_hex("01020304"));
    check_paths("one zero byte", from_hex("00"), from_hex("01020304"));
    assert_equal("all zeroes encoding",
                 std_ulogic_vector(fold_serial(from_hex("0000"))),
                 std_ulogic_vector'("0" & x"ffff"), failure);

    -- Neighbours of the zero encodings, none of which verifies.
    check_paths("sum of minus one", from_hex("0001fffd"), from_hex("01020304"));
    check_paths("sum of two", from_hex("0003fffe"), from_hex("01020304"));

    -- Accumulator encodings a pseudo-header fold hands over: both
    -- one's complement zeroes, the value the borrow bit alone stands
    -- for, and their neighbours.
    check_seed_all("init seed", checksum_acc_init_c);
    check_seed_all("plus zero seed", checksum_acc_t'("0" & x"0000"));
    check_seed_all("borrowed zero seed", checksum_acc_t'("1" & x"0001"));
    check_seed_all("borrowed minus one seed", checksum_acc_t'("1" & x"ffff"));
    check_seed_all("borrowed one seed", checksum_acc_t'("1" & x"0002"));
    check_seed_all("one seed", checksum_acc_t'("0" & x"0001"));

    -- Pseudo-header accumulators, handed over to the parametric
    -- accumulator before the datagram is folded on top of them.
    check_seeded("zero pseudo-header", from_hex("0000"), from_hex("1234edcb"),
                 from_hex("01020304"));
    check_seeded("udp pseudo-header",
                 from_hex("c0a80101c0a801020011000a"),
                 from_hex("1234edcbff007f"), from_hex("02030405"));
    check_seeded("all-ones pseudo-header",
                 from_hex("ffffffff"), from_hex("0000ffff"),
                 from_hex("03040506"));

    valid_count_v := 0;
    for trial in 0 to trial_count_c-1
    loop
      random_v := prbs_byte_string(prbs_v, prbs31, random_v'length);
      prbs_v := prbs_forward(prbs_v, prbs31, random_v'length * 8);

      len_v := 1 + (to_integer(unsigned(random_v(0))) mod max_length_c);
      if trial mod 3 /= 0 then
        -- The checksum field of a patched string sits on the last
        -- 16-bit word, so such strings have an even length.
        len_v := len_v - (len_v mod 2);
        if len_v < 4 then
          len_v := 4;
        end if;
      end if;
      data_v(0 to len_v-1) := random_v(1 to len_v);

      if trial mod 3 /= 0 then
        data_v(len_v-2 to len_v-1) := checksum_spill(fold_serial(data_v(0 to len_v-3)));
      end if;

      if trial mod 3 = 2 then
        -- Appending an all-ones word to a valid string keeps it
        -- valid and lands the 16-bit folds on the other encoding of
        -- the one's complement zero.
        data_v(len_v to len_v+1) := from_hex("ffff");
        len_v := len_v + 2;
      end if;

      check_paths("trial " & to_string(trial) & ", length " & to_string(len_v),
                  data_v(0 to len_v-1),
                  random_v(max_length_c+1 to max_length_c+8));

      -- Same corpus, reached through a pseudo-header accumulator
      -- handed over to the parametric one.
      check_seeded("trial " & to_string(trial),
                   random_v(max_length_c+1 to max_length_c+8),
                   data_v(0 to len_v-1),
                   random_v(max_length_c+1 to max_length_c+8));

      if reference_is_valid(data_v(0 to len_v-1)) then
        valid_count_v := valid_count_v + 1;
      end if;

      -- Transmit side: the checksum field takes a 16-bit slot at an
      -- even offset in the string, the accumulator folds every other
      -- byte in order.  The tail after the field decides whether the
      -- accumulator ends on an odd byte count.
      split_v := 2 * (to_integer(unsigned(random_v(max_length_c+2))) mod (len_v / 2 + 1));
      field_v := checksum_spill(fold_serial(data_v(0 to len_v-1)),
                                ((len_v - split_v) mod 2) = 1);
      assert reference_is_valid(data_v(0 to split_v-1)
                                & field_v
                                & data_v(split_v to len_v-1))
        report "trial " & to_string(trial) & ": spilled checksum "
        & to_string(field_v) & " at offset " & to_string(split_v)
        & " does not verify"
        severity failure;

      -- Same, with the field the parametric accumulator spills.  An
      -- even chunk covers the string zero-padded to a whole count of
      -- 16-bit words, so its field lands at any even offset whatever
      -- the length parity.
      par_field_v := checksum_spill(checksum_config(4),
                                    fold_pieces(data_v(0 to len_v-1),
                                                random_v(max_length_c+1
                                                         to max_length_c+8),
                                                4));
      assert reference_is_valid(data_v(0 to split_v-1)
                                & par_field_v
                                & data_v(split_v to len_v-1))
        report "trial " & to_string(trial) & ": parametric checksum "
        & to_string(par_field_v) & " at offset " & to_string(split_v)
        & " does not verify"
        severity failure;
    end loop;

    log_info("checksum accumulator OK, "
             & to_string(trial_count_c) & " trials, "
             & to_string(valid_count_v) & " of them checksummed");
    terminate(0);
  end process;

end;
