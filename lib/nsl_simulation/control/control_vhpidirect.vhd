package body control is
  
  procedure c_exit (retval : integer);
  attribute foreign of c_exit : procedure is "VHPIDIRECT exit";

  procedure c_exit (retval : Integer) is
  begin
    assert false report "must not be called" severity failure;
  end c_exit;

  procedure terminate(retval : integer) is
  begin
    c_exit(retval);
  end procedure;
  
end package body control;
