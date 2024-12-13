library std;

package body control is

  procedure terminate(retval : integer) is
  begin
    report "Terminating with error level: " & integer'image(retval)
      severity note;
    std.env.stop(retval);
  end procedure;
  
end package body control;
