package nvc_control is
  procedure c_exit (retval : integer);
  attribute foreign of c_exit : procedure is "VHPIDIRECT control_nvc_exit";
end package;

package body nvc_control is
  procedure c_exit (retval : integer) is
  begin
    assert false report "must not be called" severity failure;
  end c_exit;
end package body;

library work;

package body control is

  procedure terminate(retval : integer) is
  begin
    work.nvc_control.c_exit(retval);
  end procedure;
  
end package body control;
