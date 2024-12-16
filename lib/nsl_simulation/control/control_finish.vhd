package body control is

  use std.env.finish;

  procedure terminate(retval : integer) is
  begin
    report "Calling finish("&integer'image(retval)&")"
      severity note;
    finish(retval);
  end procedure;
  
end package body control;
