library ieee;
use std.textio.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Helper package for loading or writing binary data from/to disk
-- files.  This is mostly suited for simulation, even if some
-- synthesis tools allow to read files at elaboration stage.
package binary_io is

  alias binary_file_item is character;
  type binary_file is file of binary_file_item;

  procedure read(file handle: binary_file; data: out byte_string);
  procedure write(file handle: binary_file; data: in byte_string);

end package;

package body binary_io is

  procedure read(file handle: binary_file; data: out byte_string)
  is
    variable tmp: binary_file_item;
  begin
    for i in data'range
    loop
      read(handle, tmp);
      data(i) := to_byte(tmp);
    end loop;
  end procedure;

  procedure write(file handle: binary_file; data: in byte_string)
  is
    variable tmp: binary_file_item;
  begin
    for i in data'range
    loop
      tmp := to_character(data(i));
      write(handle, tmp);
    end loop;
  end procedure;

end package body;
