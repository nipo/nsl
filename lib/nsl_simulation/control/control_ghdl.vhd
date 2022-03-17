package body control is
  
  procedure control_simulation (Is_Stop : Boolean;
                                Has_Status : Boolean;
                                Status : Integer);
  attribute foreign of control_simulation : procedure is "GHDL intrinsic";

  procedure control_simulation (Is_Stop : Boolean;
                                Has_Status : Boolean;
                                Status : Integer) is
  begin
    assert false report "must not be called" severity failure;
  end control_simulation;

  procedure terminate(retval : integer) is
  begin
    control_simulation(true, true, retval);
  end procedure;
  
end package body control;
