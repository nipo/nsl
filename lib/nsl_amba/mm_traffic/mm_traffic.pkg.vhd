library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_amba;
use nsl_data.bytestream.all;
use nsl_amba.axi4_mm.all;

-- Traffic generation and checking for memory-mapped buses, the
-- counterpart of nsl_amba.stream_traffic.
--
-- The payload of an address is a function of that address, so a read
-- can be checked without keeping a copy of what was written.  That
-- also means a swapped or stuck address bit shows up as a data
-- mismatch instead of quietly aliasing.
package mm_traffic is

  -- Scrambles a word so that neighbouring addresses get unrelated
  -- payloads.
  function mix(value: unsigned) return unsigned;

  -- The rounds mix() is made of, so a design that cannot afford it in
  -- one cycle can spread it over several.  A round folds the word onto
  -- itself, turns it, and adds a constant: the only real delay in one
  -- is the adder's carry chain.
  --
  -- There is no multiply here on purpose.  One wide enough to mix is
  -- several of a fabric's blocks cascaded -- fifteen nanoseconds on a
  -- Spartan-6, whatever registers surround it -- and it would make the
  -- walker, rather than the memory it is pointed at, the thing that
  -- cannot be clocked.  It would also stop the walker running at all
  -- on a part with no such blocks.
  --
  -- What the payload has to do is tell addresses apart, so that a
  -- swapped or stuck address line reads back as a data mismatch rather
  -- than aliasing quietly.  These rounds do that as well as the
  -- multiply did: over a 22-bit space, one address bit in ninety
  -- thousand moves no bit of a sixteen bit bus, against two in ninety
  -- thousand before.
  --
  -- mix(v) is the rounds then a fold, and says so in its body: the
  -- pipelined and the plain form cannot drift apart.
  constant mix_round_count_c: natural := 3;

  function mix_round(value: unsigned; step: natural) return unsigned;
  function mix_fold(value: unsigned) return unsigned;

  -- Payload of one bus beat.
  function pattern(seed: unsigned;
                   beat_address: unsigned;
                   byte_count: natural) return byte_string;

  -- A beat is hashed four bytes at a time.  These expose the pieces
  -- of pattern(): what goes into the hash of one group, and how the
  -- hashes of every group become the payload.
  type hash_vector is array (natural range <>) of unsigned(31 downto 0);

  function group_count(byte_count: natural) return natural;
  function group_value(seed: unsigned;
                       beat_address: unsigned;
                       group_index: natural) return unsigned;
  function group_bytes(hash: hash_vector;
                       byte_count: natural) return byte_string;

  -- Walks a region, writing every location then reading it back.
  --
  -- With scramble_c set, transactions are visited in bit-reversed
  -- index order: still every location exactly once, but jumping across
  -- rows and banks instead of walking them.
  component axi4_mm_memory_tester is
    generic(
      config_c: config_t;
      -- First byte of the region under test
      base_address_c: natural := 0;
      -- Size of the region, as a power of two bytes
      region_byte_l2_c: natural;
      -- Bus beats per transaction
      burst_length_c: natural := 8;
      seed_c: natural := 1;
      scramble_c: boolean := false
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      start_i: in std_ulogic;

      axi_o: out master_t;
      axi_i: in slave_t;

      busy_o: out std_ulogic;
      done_o: out std_ulogic;
      error_count_o: out unsigned(31 downto 0);
      first_error_address_o: out unsigned(config_c.address_width - 1 downto 0)
      );
  end component;

end package mm_traffic;

package body mm_traffic is

  -- One fold, one turn and one addend per round.  The folds alternate
  -- direction so that a bit reaches both ends of the word, and the
  -- addends carry upwards, which is what keeps the whole from being
  -- linear in the low bits.
  type mix_step_t is
  record
    fold: natural;
    fold_up: boolean;
    turn: natural;
    addend: unsigned(31 downto 0);
  end record;

  type mix_step_vector is array (natural range <>) of mix_step_t;

  constant mix_step_c: mix_step_vector(0 to mix_round_count_c - 1) := (
    (fold => 16, fold_up => false, turn => 13, addend => x"9e3779b9"),
    (fold => 9,  fold_up => true,  turn => 17, addend => x"85ebca6b"),
    (fold => 13, fold_up => false, turn => 7,  addend => x"c2b2ae35")
    );

  function mix_round(value: unsigned; step: natural) return unsigned
  is
    constant s: mix_step_t := mix_step_c(step);
    variable v: unsigned(31 downto 0);
  begin
    v := resize(value, 32);

    if s.fold_up then
      v := v xor shift_left(v, s.fold);
    else
      v := v xor shift_right(v, s.fold);
    end if;

    return rotate_left(v, s.turn) + s.addend;
  end function;

  function mix_fold(value: unsigned) return unsigned
  is
    variable v: unsigned(31 downto 0);
  begin
    v := resize(value, 32);

    return v xor (v srl 16);
  end function;

  function mix(value: unsigned) return unsigned
  is
    variable v: unsigned(31 downto 0);
  begin
    v := resize(value, 32);

    for i in mix_step_c'range
    loop
      v := mix_round(v, i);
    end loop;

    return mix_fold(v);
  end function;

  function group_count(byte_count: natural) return natural
  is
  begin
    return (byte_count + 3) / 4;
  end function;

  function group_value(seed: unsigned;
                       beat_address: unsigned;
                       group_index: natural) return unsigned
  is
  begin
    return resize(beat_address, 32)
      xor resize(seed, 32)
      xor shift_left(to_unsigned(group_index + 1, 32), 24);
  end function;

  function group_bytes(hash: hash_vector;
                       byte_count: natural) return byte_string
  is
    alias h: hash_vector(0 to hash'length - 1) is hash;
    variable ret: byte_string(0 to byte_count - 1);
    variable position: natural;
  begin
    for g in 0 to group_count(byte_count) - 1
    loop
      for k in 0 to 3
      loop
        position := g * 4 + k;
        if position < byte_count then
          ret(position) := std_ulogic_vector(h(g)(8 * k + 7 downto 8 * k));
        end if;
      end loop;
    end loop;

    return ret;
  end function;

  function pattern(seed: unsigned;
                   beat_address: unsigned;
                   byte_count: natural) return byte_string
  is
    variable h: hash_vector(0 to group_count(byte_count) - 1);
  begin
    for g in h'range
    loop
      h(g) := mix(group_value(seed, beat_address, g));
    end loop;

    return group_bytes(h, byte_count);
  end function;

end package body mm_traffic;
