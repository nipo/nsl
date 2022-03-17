package body control is

  procedure terminate(retval : integer) is
  begin
    assert false
      report "Terminating with error level: " & integer'image(retval)
      severity failure;
  end procedure;
  
end package body control;
