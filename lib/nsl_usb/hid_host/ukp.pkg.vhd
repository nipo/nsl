library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Instruction set and elaboration-time assembler for the microcoded
-- USB host sequencer (UKP) in hid_host_engine.
--
-- The machine model and most of the instruction set come from hi631's
-- UKP microcoded USB host
-- (https://github.com/hi631/tang-nano-9K/tree/master/NES) as extended
-- by nand2mario's usb_hid_host
-- (https://github.com/nand2mario/usb_hid_host).  This implementation
-- re-encodes the instructions to fixed-width words, adds CALL/RET and
-- CRC checking, and moves assembly to VHDL elaboration.
--
-- A program is a constant of program_t built by concatenating the
-- constructor functions below.  assemble() resolves labels and
-- produces the ROM image consumed by the engine.  All assembly
-- happens at elaboration; assembly errors (duplicate or undefined
-- label, out-of-range operand) fail elaboration with an assertion.
--
-- Machine model, for a low-speed USB host bit-banging D+/D-:
--
-- * The engine clock runs at 8 cycles per bit time (12MHz for the
--   1.5Mb/s low-speed rate).
--
-- * W is an 8-bit down-counter, loaded by LDI, used by DJNZ for loops
--   and by IN as a sample-count timeout.
--
-- * C is a 1-bit flag, toggled by TOGGLE, tested by BC.  Programs
--   conventionally use it as the "device enumerated, identity
--   registers are valid" state; the engine exports it as such.
--
-- * A single-depth link register supports CALL/RET.  Nested calls are
--   not detected by the assembler; the inner CALL silently clobbers
--   the link.
--
-- * A free-running millisecond timer paces WAIT.  It is never reset
--   by instructions, so consecutive WAITs align to a 1ms grid.
--
-- * The receiver hardware runs during IN: it recovers bit timing from
--   line transitions, NRZI-decodes, removes stuffed bits, captures
--   the PID, stores payload bytes (CRC16 included) to the receive
--   buffer, and checks CRC16.  The NAK flag (BNAK) is set by START
--   and cleared when a packet with any PID other than NAK or STALL is
--   received, so a receive that times out with no response reads as
--   NAKed.  The ERR flag (BERR) is cleared by START and set when a
--   DATA packet fails CRC16 check.  SAVE copies receive buffer bytes
--   to the identity registers defined in the hid_host package.
package ukp is

  type opcode_t is (
    -- No effect.
    UKP_NOP,
    -- Load 8-bit constant into W.
    UKP_LDI,
    -- Stall until D- goes low (start of packet on low-speed, where
    -- idle J state has D- high), then reset receive state: bit
    -- counter and CRC cleared, ERR flag cleared, NAK flag set.
    UKP_START,
    -- Drive the bus with 4 raw (D+, D-) symbol pairs, one per bit
    -- time, most-significant bit first, without NRZI encoding nor bit
    -- stuffing.  Operand bits 7..4 are the D+ values, bits 3..0 the
    -- D- values.  Used for EOP and other raw line sequences.
    UKP_OUT4,
    -- At the next bit boundary, enable the driver with both lines low
    -- (single-ended zero).  The state persists until a subsequent
    -- output instruction.
    UKP_OUT0,
    -- At the next bit boundary, release the bus driver.
    UKP_HIZ,
    -- Transmit one byte, least-significant bit first, NRZI-encoded
    -- with bit stuffing, driver enabled.  Consecutive OUTB do not
    -- reset NRZI nor bit stuffing state; HIZ does.
    UKP_OUTB,
    -- Return to the instruction following the last CALL.
    UKP_RET,
    -- Branch if D- is low (no device connected, as the low-speed
    -- device pull-up holds D- high when idle).
    UKP_BZ,
    -- Branch if C flag is set.
    UKP_BC,
    -- Branch if the last receive attempt got a NAK or STALL PID, or
    -- timed out without receiving any packet.
    UKP_BNAK,
    -- Branch if the last received DATA packet failed CRC16 check.
    UKP_BERR,
    -- Decrement W, branch if the result is not zero.
    UKP_DJNZ,
    -- Toggle the C flag.
    UKP_TOGGLE,
    -- Copy receive buffer byte (operand bits 3..0) to identity
    -- register (operand bits 7..4).
    UKP_SAVE,
    -- Run the receiver.  Completes at EOP (single-ended zero sampled)
    -- or after W bit samples, whichever comes first.  W decrements on
    -- every sample taken.
    UKP_IN,
    -- Stall until the next tick of the free-running millisecond
    -- timer.
    UKP_WAIT,
    -- Unconditional branch.
    UKP_JMP,
    -- Save the address of the next instruction to the link register
    -- and branch.
    UKP_CALL,
    -- Pseudo-instruction defining a label position.  Emits nothing.
    UKP_LABEL
    );

  subtype label_t is natural range 0 to 63;

  type instruction_t is
  record
    opcode: opcode_t;
    -- Immediate value, packed operand, or label index for
    -- branch-family opcodes and UKP_LABEL.
    operand: natural;
  end record;

  type program_t is array (natural range <>) of instruction_t;

  -- All constructors return a program_t slice so that programs
  -- compose with "&".
  function lbl(l: label_t) return program_t;
  function ldi(v: natural) return program_t;
  function start return program_t;
  function out4(dp, dm: std_ulogic_vector(3 downto 0)) return program_t;
  function out0 return program_t;
  function hiz return program_t;
  function outb(v: byte) return program_t;
  -- One OUTB per byte, in order.
  function out_bytes(v: byte_string) return program_t;
  function ret return program_t;
  function bz(l: label_t) return program_t;
  function bc(l: label_t) return program_t;
  function bnak(l: label_t) return program_t;
  function berr(l: label_t) return program_t;
  function djnz(l: label_t) return program_t;
  function toggle return program_t;
  function save(reg, index: natural) return program_t;
  function usb_in return program_t;
  function wait_frame return program_t;
  function jmp(l: label_t) return program_t;
  function call(l: label_t) return program_t;
  function nop return program_t;

  -- 16-bit instruction word: opcode_encode() of the opcode in bits
  -- 15..11, operand in bits 10..0.  Word address space is therefore
  -- 2048 instructions.
  subtype word_t is std_ulogic_vector(15 downto 0);
  type rom_t is array (natural range <>) of word_t;

  function opcode_encode(op: opcode_t) return std_ulogic_vector;

  -- Number of words assemble() will emit for a program (labels emit
  -- nothing).
  function instruction_count(p: program_t) return natural;

  -- Two-pass assembly: resolve label addresses, then emit words with
  -- branch operands substituted.
  function assemble(p: program_t) return rom_t;

  function to_string(i: instruction_t) return string;

end package;

package body ukp is

  function single(op: opcode_t; operand: natural) return program_t is
    variable ret: program_t(0 to 0);
  begin
    ret(0).opcode := op;
    ret(0).operand := operand;
    return ret;
  end function;

  function lbl(l: label_t) return program_t is
  begin
    return single(UKP_LABEL, l);
  end function;

  function ldi(v: natural) return program_t is
  begin
    assert v < 256
      report "LDI immediate out of range: " & integer'image(v)
      severity failure;
    return single(UKP_LDI, v);
  end function;

  function start return program_t is
  begin
    return single(UKP_START, 0);
  end function;

  function out4(dp, dm: std_ulogic_vector(3 downto 0)) return program_t is
  begin
    return single(UKP_OUT4,
                  to_integer(unsigned(dp)) * 16 + to_integer(unsigned(dm)));
  end function;

  function out0 return program_t is
  begin
    return single(UKP_OUT0, 0);
  end function;

  function hiz return program_t is
  begin
    return single(UKP_HIZ, 0);
  end function;

  function outb(v: byte) return program_t is
  begin
    return single(UKP_OUTB, to_integer(unsigned(v)));
  end function;

  function out_bytes(v: byte_string) return program_t is
    variable ret: program_t(0 to v'length-1);
    variable i: natural := 0;
  begin
    for b in v'range loop
      ret(i to i) := outb(v(b));
      i := i + 1;
    end loop;
    return ret;
  end function;

  function ret return program_t is
  begin
    return single(UKP_RET, 0);
  end function;

  function bz(l: label_t) return program_t is
  begin
    return single(UKP_BZ, l);
  end function;

  function bc(l: label_t) return program_t is
  begin
    return single(UKP_BC, l);
  end function;

  function bnak(l: label_t) return program_t is
  begin
    return single(UKP_BNAK, l);
  end function;

  function berr(l: label_t) return program_t is
  begin
    return single(UKP_BERR, l);
  end function;

  function djnz(l: label_t) return program_t is
  begin
    return single(UKP_DJNZ, l);
  end function;

  function toggle return program_t is
  begin
    return single(UKP_TOGGLE, 0);
  end function;

  function save(reg, index: natural) return program_t is
  begin
    assert reg < 16 and index < 16
      report "SAVE operand out of range"
      severity failure;
    return single(UKP_SAVE, reg * 16 + index);
  end function;

  function usb_in return program_t is
  begin
    return single(UKP_IN, 0);
  end function;

  function wait_frame return program_t is
  begin
    return single(UKP_WAIT, 0);
  end function;

  function jmp(l: label_t) return program_t is
  begin
    return single(UKP_JMP, l);
  end function;

  function call(l: label_t) return program_t is
  begin
    return single(UKP_CALL, l);
  end function;

  function nop return program_t is
  begin
    return single(UKP_NOP, 0);
  end function;

  function opcode_encode(op: opcode_t) return std_ulogic_vector is
  begin
    assert op /= UKP_LABEL
      report "UKP_LABEL has no encoding"
      severity failure;
    return std_ulogic_vector(to_unsigned(opcode_t'pos(op), 5));
  end function;

  function instruction_count(p: program_t) return natural is
    variable ret: natural := 0;
  begin
    for i in p'range loop
      if p(i).opcode /= UKP_LABEL then
        ret := ret + 1;
      end if;
    end loop;
    return ret;
  end function;

  function is_branch(op: opcode_t) return boolean is
  begin
    case op is
      when UKP_BZ | UKP_BC | UKP_BNAK | UKP_BERR
        | UKP_DJNZ | UKP_JMP | UKP_CALL =>
        return true;
      when others =>
        return false;
    end case;
  end function;

  function assemble(p: program_t) return rom_t is
    type label_map_t is array (label_t) of integer;
    variable labels: label_map_t := (others => -1);
    variable ret: rom_t(0 to instruction_count(p)-1);
    variable address: natural := 0;
    variable operand: natural;
  begin
    for i in p'range loop
      if p(i).opcode = UKP_LABEL then
        assert labels(p(i).operand) = -1
          report "Duplicate label " & integer'image(p(i).operand)
          severity failure;
        labels(p(i).operand) := address;
      else
        address := address + 1;
      end if;
    end loop;

    address := 0;
    for i in p'range loop
      if p(i).opcode /= UKP_LABEL then
        operand := p(i).operand;
        if is_branch(p(i).opcode) then
          assert labels(operand) /= -1
            report "Undefined label " & integer'image(operand)
            severity failure;
          operand := labels(operand);
        end if;
        assert operand < 2048
          report "Operand out of range at address " & integer'image(address)
          severity failure;
        ret(address) := opcode_encode(p(i).opcode)
          & std_ulogic_vector(to_unsigned(operand, 11));
        address := address + 1;
      end if;
    end loop;
    return ret;
  end function;

  function to_string(i: instruction_t) return string is
  begin
    return opcode_t'image(i.opcode) & " " & integer'image(i.operand);
  end function;

end package body;
