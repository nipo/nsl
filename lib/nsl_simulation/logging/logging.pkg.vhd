use std.textio.all;

package logging is

  type log_level_t is (
    LOG_LEVEL_DEBUG,
    LOG_LEVEL_INFO,
    LOG_LEVEL_WARNING,
    LOG_LEVEL_ERROR,
    LOG_LEVEL_FATAL
    );
  function to_string(level : log_level_t) return string;

  procedure log(level : log_level_t; message : string);

  procedure log_debug(message : string);
  procedure log_info(message : string);
  procedure log_warning(message : string);
  procedure log_error(message : string);
  procedure log_fatal(message : string);

  subtype log_context is string;

  procedure log_debug(context: log_context; message : string);
  procedure log_info(context: log_context; message : string);
  procedure log_warning(context: log_context; message : string);
  procedure log_error(context: log_context; message : string);
  procedure log_fatal(context: log_context; message : string);

end package;

package body logging is
  
  function to_string(level : log_level_t) return string is
  begin
    case level is
      when LOG_LEVEL_DEBUG   => return "DBG";
      when LOG_LEVEL_INFO    => return "INF";
      when LOG_LEVEL_WARNING => return "WRN";
      when LOG_LEVEL_ERROR   => return "ERR";
      when others            => return "FTL";
    end case;
  end function;
  
  procedure log(level : log_level_t; message : string) is
    variable l:line;
  begin
    write(l, string'("@"));
    write(l, integer'image(integer(NOW / 1 ns)));
    write(l, string'("ns ["));
    write(l, to_string(level));
    write(l, string'("] "));
    write(l, message);
    writeline(output, l);
  end procedure;

  procedure log_debug(message : string) is
  begin
    log(LOG_LEVEL_DEBUG, message);
  end procedure;

  procedure log_info(message : string) is
  begin
    log(LOG_LEVEL_INFO, message);
  end procedure;

  procedure log_warning(message : string) is
  begin
    log(LOG_LEVEL_WARNING, message);
  end procedure;

  procedure log_error(message : string) is
  begin
    log(LOG_LEVEL_ERROR, message);
  end procedure;

  procedure log_fatal(message : string) is
  begin
    log(LOG_LEVEL_FATAL, message);
  end procedure;

  procedure log_debug(context: log_context; message : string) is
  begin
    log_debug("[" & context & "] " & message);
  end procedure;

  procedure log_info(context: log_context; message : string) is
  begin
    log_info("[" & context & "] " & message);
  end procedure;

  procedure log_warning(context: log_context; message : string) is
  begin
    log_warning("[" & context & "] " & message);
  end procedure;

  procedure log_error(context: log_context; message : string) is
  begin
    log_error("[" & context & "] " & message);
  end procedure;

  procedure log_fatal(context: log_context; message : string) is
  begin
    log_fatal("[" & context & "] " & message);
  end procedure;
  
end package body;
