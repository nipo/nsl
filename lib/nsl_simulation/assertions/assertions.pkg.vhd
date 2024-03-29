library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

package assertions is

  procedure assert_equal(what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level);

  procedure assert_match(what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in integer;
                         b : in integer;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in boolean;
                         b : in boolean;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in std_ulogic;
                         b : in std_ulogic;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in bit_vector;
                         b : in bit_vector;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level);

  procedure assert_match(what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in unsigned;
                         b : in unsigned;
                         sev : in severity_level);

  procedure assert_equal(what: in string;
                         a : in string;
                         b : in string;
                         sev : in severity_level);
    
  procedure assert_equal(what: in string;
                         a : in byte_string;
                         b : in byte_string;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level);

  procedure assert_match(context: in log_context;
                         what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in integer;
                         b : in integer;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in boolean;
                         b : in boolean;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_ulogic;
                         b : in std_ulogic;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in bit_vector;
                         b : in bit_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level);

  procedure assert_match(context: in log_context;
                         what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in unsigned;
                         b : in unsigned;
                         sev : in severity_level);
  
  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in string;
                         b : in string;
                         sev : in severity_level);
  
  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in byte_string;
                         b : in byte_string;
                         sev : in severity_level);

end package;

package body assertions is

  procedure assert_equal_failure(context: in log_context;
                                 what: in string;
                                 a : in string;
                                 b : in string;
                                 sev : in severity_level) is
  begin
    log_error(context, "while " & what & ", " & a & " /= " & b);
    if sev = FAILURE then
      nsl_simulation.control.terminate(1);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure("UNK", what,
                           """" & to_string(a) & """ (x""" & to_hex_string(a) & """)",
                           """" & to_string(b) & """ (x""" & to_hex_string(b) & """)",
                           sev);
    end if;
  end procedure;

  procedure assert_match(what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level) is
  begin
    if not std_match(a, b) then
      assert_equal_failure("UNK", what,
                           """" & to_string(a) & """ (x""" & to_hex_string(a) & """)",
                           """" & to_string(b) & """ (x""" & to_hex_string(b) & """)",
                           sev);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in integer;
                         b : in integer;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure("UNK", what,
                           """" & to_string(a) & """",
                           """" & to_string(b) & """",
                           sev);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in boolean;
                         b : in boolean;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure("UNK", what,
                           """" & to_string(a) & """",
                           """" & to_string(b) & """",
                           sev);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in std_ulogic;
                         b : in std_ulogic;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal("UNK", what, a, b, sev);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in bit_vector;
                         b : in bit_vector;
                         sev : in severity_level) is
  begin
    assert_equal("UNK", what, to_stdulogicvector(a), to_stdulogicvector(b), sev);
  end procedure;

  procedure assert_equal(what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level) is
  begin
    assert_equal("UNK", what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_equal(what: in string;
                         a : in unsigned;
                         b : in unsigned;
                         sev : in severity_level) is
  begin
    assert_equal("UNK", what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_match(what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level) is
  begin
    assert_match("UNK", what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_match(what: in string;
                         a : in unsigned;
                         b : in unsigned;
                         sev : in severity_level) is
  begin
    assert_match("UNK", what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;
  
  procedure assert_equal(what: in string;
                         a : in byte_string;
                         b : in byte_string;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure("UNK", what,
                           to_string(a),
                           to_string(b),
                           sev);
    end if;
  end procedure;

  procedure assert_equal(what: in string;
                         a : in string;
                         b : in string;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure("UNK", what, a, b, sev);
    end if;
  end procedure;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure(context, what,
                           """" & to_string(a) & """ (x""" & to_hex_string(a) & """)",
                           """" & to_string(b) & """ (x""" & to_hex_string(b) & """)",
                           sev);
    end if;
  end procedure;

  procedure assert_match(context: in log_context;
                         what: in string;
                         a : in std_ulogic_vector;
                         b : in std_ulogic_vector;
                         sev : in severity_level) is
  begin
    if not std_match(a, b) then
      assert_equal_failure(context, what,
                           """" & to_string(a) & """ (x""" & to_hex_string(a) & """)",
                           """" & to_string(b) & """ (x""" & to_hex_string(b) & """)",
                           sev);
    end if;
  end procedure;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in integer;
                         b : in integer;
                         sev : in severity_level) is
 begin
    if a /= b then
      assert_equal_failure(context, what,
                           """" & to_string(a) & """",
                           """" & to_string(b) & """",
                           sev);
    end if;
 end;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in boolean;
                         b : in boolean;
                         sev : in severity_level) is
 begin
    if a /= b then
      assert_equal_failure(context, what,
                           """" & to_string(a) & """",
                           """" & to_string(b) & """",
                           sev);
    end if;
 end;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in bit_vector;
                         b : in bit_vector;
                         sev : in severity_level) is
  begin
    assert_equal(context, what, to_stdulogicvector(a), to_stdulogicvector(b), sev);
  end procedure;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level) is
  begin
    assert_equal(context, what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in std_ulogic;
                         b : in std_ulogic;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure(context, what, "'" & to_string(a) & "'", "'" & to_string(b) & "'", sev);
    end if;
  end procedure;

  procedure assert_match(context: in log_context;
                         what: in string;
                         a : in std_logic_vector;
                         b : in std_logic_vector;
                         sev : in severity_level) is
  begin
    assert_match(context, what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in unsigned;
                         b : in unsigned;
                         sev : in severity_level) is
  begin
    assert_equal(context, what, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;
  
  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in byte_string;
                         b : in byte_string;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure(context, what,
                           to_string(a),
                           to_string(b),
                           sev);
    end if;
  end procedure;
  
  procedure assert_equal(context: in log_context;
                         what: in string;
                         a : in string;
                         b : in string;
                         sev : in severity_level) is
  begin
    if a /= b then
      assert_equal_failure(context, what, a, b, sev);
    end if;
  end procedure;

end package body;

