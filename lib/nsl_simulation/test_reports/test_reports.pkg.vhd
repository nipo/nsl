use std.textio.all;

package test_reports is

  file test_report_f : text;
  constant test_report_path_c : string := "report.txt";
  
  procedure test_suite_start(suite_name : in string);
  
  procedure test_case_result(test_number : in integer; name : in string; test_status: in boolean);

  procedure test_suite_end;

end package;

package body test_reports is

  shared variable file_is_open : boolean := false;

  procedure test_suite_start(suite_name : in string) is
    variable status: file_open_status;
    variable l : line;
  begin
    if not file_is_open then
    file_open(status => status,
              f => test_report_f,
              external_name => test_report_path_c,
              open_kind => WRITE_MODE);

    if status = OPEN_OK then
      file_is_open := true;
      write(l, string'("[TestSuite] ") & suite_name);
      writeline(test_report_f, l);
    else
      file_is_open := false;
      report "Opening " & test_report_path_c & " failed"
        severity warning;
    end if;
    else
      write(l, string'("[TestSuite] ") & suite_name);
      writeline(test_report_f, l);
    end if;
  end procedure;

  procedure test_case_result(test_number : in integer; name : in string; test_status: in boolean) is
    variable l : line;
  begin
    if not file_is_open then
      test_suite_start("UNKNOWN TEST SUITE");
    end if;

    if not file_is_open then
      return;
    end if;

    write(l, string'("[TestCase] #"));
    write(l, integer'image(test_number));
    write(l, string'(" <"));
    write(l, name);
    write(l, string'("> "));
    if test_status then
      write(l, string'("PASS"));
    else
      write(l, string'("FAIL"));
    end if;
    writeline(test_report_f, l);
  end procedure;

  procedure test_suite_end is
  begin
    if not file_is_open then
      return;
    end if;

    file_close(test_report_f);
    file_is_open := false;
  end procedure;
    
end package body;
