library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_simulation.text.all;

package assertions is

  procedure assert_equal(context: in string;
                         a, b: in std_ulogic_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in string;
                         a, b: in bit_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in string;
                         a, b: in std_logic_vector;
                         sev : in severity_level);

  procedure assert_equal(context: in string;
                         a, b: in unsigned;
                         sev : in severity_level);
  
  procedure assert_equal(context: in string;
                         a, b: in byte_string;
                         sev : in severity_level);

end package;

package body assertions is

  procedure assert_equal(context: in string;
                         a, b: in std_ulogic_vector;
                         sev : in severity_level) is
  begin
    assert a = b
      report """" & to_string(a) & "' (x""" & to_hex_string(a)
      & """) /= """ & to_string(b) & """ (x""" & to_hex_string(b)
      & """), context: " & context
      severity sev;
  end procedure;

  procedure assert_equal(context: in string;
                         a, b: in bit_vector;
                         sev : in severity_level) is
  begin
    assert_equal(context, to_stdulogicvector(a), to_stdulogicvector(b), sev);
  end procedure;

  procedure assert_equal(context: in string;
                         a, b: in std_logic_vector;
                         sev : in severity_level) is
  begin
    assert_equal(context, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;

  procedure assert_equal(context: in string;
                         a, b: in unsigned;
                         sev : in severity_level) is
  begin
    assert_equal(context, std_ulogic_vector(a), std_ulogic_vector(b), sev);
  end procedure;
  
  procedure assert_equal(context: in string;
                         a, b: in byte_string;
                         sev : in severity_level) is
  begin
    assert a = b
      report to_string(a) & " /= " & to_string(b) & ", context: " & context
      severity sev;
  end procedure;

end package body;

