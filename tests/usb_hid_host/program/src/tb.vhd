library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_usb.ukp.all;
use nsl_usb.hid_program.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture arch of tb is

  constant lbl_backward_c: label_t := 7;
  constant lbl_forward_c: label_t := 3;

  -- Assembly of this program is checked word by word below.  It uses
  -- every opcode that carries an operand, both branch directions, and
  -- a label placed at the very last instruction.
  constant test_program_c: program_t :=
    lbl(lbl_backward_c)
    & ldi(42)
    & out4(dp => "1010", dm => "0101")
    & save(6, 9)
    & out_bytes(from_hex("deadbeef"))
    & bz(lbl_forward_c)
    & bc(lbl_forward_c)
    & bnak(lbl_backward_c)
    & berr(lbl_backward_c)
    & djnz(lbl_backward_c)
    & call(lbl_forward_c)
    & jmp(lbl_backward_c)
    & start
    & usb_in
    & out0
    & hiz
    & toggle
    & wait_frame
    & ret
    & lbl(lbl_forward_c)
    & nop;

  -- Word encoding is the 5-bit opcode_t'pos in bits 15 downto 11 and
  -- the operand in bits 10 downto 0.  The backward label resolves to
  -- address 0, the forward one to address 21.
  constant expected_c: rom_t(0 to 21) := (
    0 => x"082a",
    1 => x"18a5",
    2 => x"7069",
    3 => x"30de",
    4 => x"30ad",
    5 => x"30be",
    6 => x"30ef",
    7 => x"4015",
    8 => x"4815",
    9 => x"5000",
    10 => x"5800",
    11 => x"6000",
    12 => x"9015",
    13 => x"8800",
    14 => x"1000",
    15 => x"7800",
    16 => x"2000",
    17 => x"2800",
    18 => x"6800",
    19 => x"8000",
    20 => x"3800",
    21 => x"0000");

  constant test_rom_c: rom_t := assemble(test_program_c);

  constant hid_rom_c: rom_t := assemble(hid_program(hid_program_defaults_c));

  function word_image(w: word_t) return string
  is
  begin
    return integer'image(to_integer(unsigned(w)));
  end function;

begin

  check: process
  begin
    assert instruction_count(test_program_c) = expected_c'length
      report "Test program has "
      & integer'image(instruction_count(test_program_c))
      & " instructions, expected " & integer'image(expected_c'length)
      severity failure;

    assert test_rom_c'length = expected_c'length
      report "Assembled ROM has " & integer'image(test_rom_c'length)
      & " words, expected " & integer'image(expected_c'length)
      severity failure;

    for i in expected_c'range loop
      assert test_rom_c(i) = expected_c(i)
        report "Word " & integer'image(i) & " is " & word_image(test_rom_c(i))
        & ", expected " & word_image(expected_c(i))
        severity failure;
    end loop;

    report "HID host program is " & integer'image(hid_rom_c'length)
      & " instructions"
      severity note;

    assert hid_rom_c'length > 80
      report "HID host program is implausibly short: "
      & integer'image(hid_rom_c'length) & " instructions"
      severity failure;

    terminate(0);
    wait;
  end process;

end architecture;
