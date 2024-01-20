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
  impure function file_size(file_name: string) return natural;
  impure function file_load(file_name: string) return byte_string;

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

  impure function file_size(file_name: string) return natural
  is
    file handle: binary_file;
    variable status: file_open_status;
    variable ret: natural := 0;
    variable tmp: byte_string(0 to 0);
  begin
    file_open(status => status,
              f => handle,
              external_name => file_name,
              open_kind => READ_MODE);

    assert status = OPEN_OK
      report "Opening "&file_name&" failed, returning zero size"
      severity warning;

    if status /= OPEN_OK then
      return 0;
    end if;

    while not endfile(handle)
    loop
      read(handle, tmp);
      ret := ret + 1;
    end loop;

    file_close(handle);

    return ret;
  end function;

  impure function file_load_smaller(file_name: string; low, high: natural) return byte_string
  is
    file handle: binary_file;
    constant size: natural := (low + high + 1) / 2;
    variable status: file_open_status;
    variable ret: byte_string(0 to size-1);
    variable at_end1, at_end2: boolean;
  begin
    if size = 0 then
      return null_byte_string;
    end if;

    file_open(status => status,
              f => handle,
              external_name => file_name,
              open_kind => READ_MODE);

    assert status = OPEN_OK
      report "Opening "&file_name&" failed"
      severity failure;

    if status /= OPEN_OK then
      return null_byte_string;
    end if;

    read(handle, ret(0 to ret'right-1));
    at_end1 := endfile(handle);
    read(handle, ret(ret'right to ret'right));
    at_end2 := endfile(handle);
    file_close(handle);

    if not at_end1 and at_end2 then
      return ret;
    elsif at_end1 then
      return file_load_smaller(file_name, low, size);
    else
      return file_load_smaller(file_name, size, high);
    end if;
  end function;

  impure function file_load_larger(file_name: string; size: natural) return byte_string
  is
    file handle: binary_file;
    variable status: file_open_status;
    variable ret: byte_string(0 to size-1);
    variable at_end: boolean;
  begin
    if size = 0 then
      return null_byte_string;
    end if;

    file_open(status => status,
              f => handle,
              external_name => file_name,
              open_kind => READ_MODE);

    assert status = OPEN_OK
      report "Opening "&file_name&" failed"
      severity failure;

    if status /= OPEN_OK then
      return null_byte_string;
    end if;

    read(handle, ret);
    at_end := endfile(handle);
    file_close(handle);

    if not at_end then
      return file_load_larger(file_name, size * 2);
    else
      return file_load_smaller(file_name, size / 2, size);
    end if;
  end function;

  impure function file_load(file_name: string) return byte_string
  is
    file handle: binary_file;
    variable status: file_open_status;
    constant size: natural := file_size(file_name);
    variable ret: byte_string(0 to size-1);
  begin
    if size = 0 then
      return null_byte_string;
    end if;

    file_open(status => status,
              f => handle,
              external_name => file_name,
              open_kind => READ_MODE);

    assert status = OPEN_OK
      report "Opening "&file_name&" failed"
      severity failure;

    read(handle, ret);

    file_close(handle);

    return ret;
  end function;

end package body;
