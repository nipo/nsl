library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package file_io is

  procedure slv_read(buf: inout line; v: out std_logic_vector);
  procedure slv_write(buf: inout line; v: in std_logic_vector);

end package;

package body file_io is

  procedure slv_read(buf: inout line; v: out std_logic_vector) is
    variable c: character;
  begin
    for i in v'range loop
      read(buf, c);
      case c is
        when 'X' => v(i) := 'X';
        when 'U' => v(i) := 'U';
        when 'Z' => v(i) := 'Z';
        when '0' => v(i) := '0';
        when '1' => v(i) := '1';
        when '-' => v(i) := '-';
        when 'W' => v(i) := 'W';
        when 'H' => v(i) := 'H';
        when 'L' => v(i) := 'L';
        when others => v(i) := '0';
      end case;
    end loop;
  end procedure slv_read;

  procedure slv_write(buf: inout line; v: in std_logic_vector) is
    variable c: character;
  begin
    for i in v'range loop
      case v(i) is
        when 'X' => c := 'X';
        when 'U' => c := 'U';
        when 'Z' => c := 'Z';
        when '0' => c := '0';
        when '1' => c := '1';
        when '-' => c := '-';
        when 'W' => c := 'W';
        when 'H' => c := 'H';
        when 'L' => c := 'L';
        when others => c := '0';
      end case;
      write(buf, c);
    end loop;
  end procedure slv_write;

end package body;

