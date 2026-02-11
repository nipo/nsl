library nsl_data;

package body shell is

  impure function shell_run_command(cmd: string) return integer
  is
  begin
    return 2;
  end function;

  impure function background_process_run(cmd: string)
    return integer
  is
  begin
    return -1;
  end function;

  impure function background_process_wait(pid: integer)
    return integer
  is
  begin
    return -1;
  end function;

end package body;
