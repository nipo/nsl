library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Script of the microcoded DMA bench.
--
-- The dma_vectors_* packages hold scripts the DMA's reference model
-- (fpix, host/acrobe_plugin/fpix/m2m_dma/vectors.py) generates.  A
-- script is a sequence of operations, each a header word (opcode in
-- bits [7:0], length in words, header included, in bits [31:16])
-- followed by its operands.  See the generator for their meaning.
package dma_vector is

  subtype word_t is unsigned(31 downto 0);
  type word_vector is array (natural range <>) of word_t;
  type natural_vector is array (natural range <>) of natural;

  constant op_end_c : natural := 0;
  constant op_log_c : natural := 1;
  constant op_mem_write_c : natural := 2;
  constant op_mem_check_c : natural := 3;
  constant op_reset_c : natural := 4;
  constant op_debug_c : natural := 5;
  constant op_wait_regs_c : natural := 6;
  constant op_delay_c : natural := 7;
  constant op_apb_write_c : natural := 8;
  constant op_apb_check_c : natural := 9;
  constant op_check_irq_c : natural := 10;
  constant op_periph_c : natural := 11;
  constant op_sync_c : natural := 12;
  constant op_ignore_c : natural := 13;
  constant op_check_busy_c : natural := 14;
  constant op_mem_fill_c : natural := 15;
  constant op_check_taken_c : natural := 16;
  constant op_expect_read_c : natural := 20;
  constant op_expect_write_c : natural := 21;
  constant op_expect_ack_c : natural := 22;

  -- Channel number meaning none in expectations
  constant no_channel_c : natural := 16#ff#;

  -- Operand offsets of expectations
  constant xfer_channel_c : natural := 1;
  constant xfer_addr_c : natural := 2;
  constant xfer_beats_c : natural := 3;
  constant xfer_size_c : natural := 4;
  constant xfer_incr_c : natural := 5;
  constant xfer_cache_c : natural := 6;
  constant xfer_prot_c : natural := 7;
  constant xfer_resp_c : natural := 8;
  constant xfer_after_channel_c : natural := 9;
  constant xfer_after_count_c : natural := 10;
  -- Byte count, bit 30 set when the data is unknown
  constant xfer_bytes_c : natural := 11;
  constant xfer_data_c : natural := 12;

  constant ack_periph_c : natural := 1;
  constant ack_type_c : natural := 2;
  constant ack_channel_c : natural := 3;
  constant ack_reads_c : natural := 4;
  constant ack_writes_c : natural := 5;

  function opcode(w : word_t) return natural;
  function op_length(w : word_t) return natural;
  -- Operand as a natural, for operands below 2**31
  function nat(w : word_t) return natural;
  -- Byte k of the byte string packed little endian from word base on
  function byte_at(s : word_vector; base, k : natural) return byte;
  function bytes_at(s : word_vector; base, count : natural) return byte_string;
  function text_at(s : word_vector; base, count : natural) return string;
  -- Index of the first operation at or after from with the given
  -- opcode and first operand, s'high + 1 if none
  function find(s : word_vector; from, op, operand : natural) return natural;

end package;

package body dma_vector is

  function opcode(w : word_t) return natural is
  begin
    return to_integer(w(7 downto 0));
  end function;

  function op_length(w : word_t) return natural is
  begin
    return to_integer(w(31 downto 16));
  end function;

  function nat(w : word_t) return natural is
  begin
    assert w(31) = '0'
      report "Operand too large for a natural"
      severity failure;
    return to_integer(w(30 downto 0));
  end function;

  function byte_at(s : word_vector; base, k : natural) return byte is
    constant w : word_t := s(base + k / 4);
  begin
    return std_ulogic_vector(w(8 * (k mod 4) + 7 downto 8 * (k mod 4)));
  end function;

  function bytes_at(s : word_vector; base, count : natural) return byte_string is
    variable ret : byte_string(0 to count-1);
  begin
    for k in ret'range
    loop
      ret(k) := byte_at(s, base, k);
    end loop;
    return ret;
  end function;

  function text_at(s : word_vector; base, count : natural) return string is
    variable ret : string(1 to count);
  begin
    for k in 0 to count-1
    loop
      ret(k + 1) := character'val(to_integer(unsigned(byte_at(s, base, k))));
    end loop;
    return ret;
  end function;

  function find(s : word_vector; from, op, operand : natural) return natural is
    variable i : natural := from;
  begin
    while i <= s'high
    loop
      if opcode(s(i)) = op and s(i + 1) = to_unsigned(operand, 32) then
        return i;
      end if;
      if opcode(s(i)) = op_end_c then
        return s'high + 1;
      end if;
      i := i + op_length(s(i));
    end loop;
    return s'high + 1;
  end function;

end package body;
