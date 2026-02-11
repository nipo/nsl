library nsl_data, nsl_simulation;

package shell is

  impure function shell_run_command(cmd: string) return integer;
  impure function shell_background_process_run(cmd: string) return integer;
  impure function shell_background_process_wait(pid: integer) return integer;
  
end package;
