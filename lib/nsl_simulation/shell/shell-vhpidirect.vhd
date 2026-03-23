library nsl_data;

package body shell is
  
  impure function run_command(cmd: string)
    return integer
  is
  begin
    assert false report "Should not be called" severity failure;
  end function;

  attribute foreign of run_command: function is "VHPIDIRECT shell-vhpidirect.so run_command";

  impure function bg_process_run(cmd: string)
    return integer
  is
  begin
    assert false report "Should not be called" severity failure;
  end function;

  attribute foreign of bg_process_run: function is "VHPIDIRECT shell-vhpidirect.so bg_process_run";

  impure function bg_process_wait(pid: integer)
    return integer
  is
  begin
    assert false report "Should not be called" severity failure;
  end function;

  attribute foreign of bg_process_wait: function is "VHPIDIRECT shell-vhpidirect.so bg_process_wait";

  impure function shell_run_command(cmd: string) return integer
  is
  begin
    return run_command( cmd & NUL );
  end function;

  impure function shell_background_process_run(cmd: string)
    return integer
  is
  begin
    return bg_process_run(cmd & NUL);
  end function;

  impure function shell_background_process_wait(pid: integer)
    return integer
  is
  begin
    return bg_process_wait(pid);
  end function;
  
end package body;
