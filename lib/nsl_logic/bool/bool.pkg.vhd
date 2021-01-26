library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package bool is

  function to_boolean(i : std_ulogic) return boolean;
  function to_logic(i : boolean) return std_ulogic;

  function if_else(i : boolean; a, b : integer) return integer;
  function if_else(i : boolean; a, b : std_ulogic) return std_ulogic;
  function if_else(i : boolean; a, b : std_ulogic_vector) return std_ulogic_vector;
  function if_else(i : boolean; a, b : std_logic_vector) return std_logic_vector;
  function if_else(i : boolean; a, b : unsigned) return unsigned;

end package bool;

package body bool is

  function to_boolean(i : std_ulogic) return boolean is
  begin
    return i = '1';
  end function;

  function to_logic(i : boolean) return std_ulogic is
  begin
    if i then
      return '1';
    else
      return '0';
    end if;
  end function;

  function if_else(i : boolean; a, b : integer) return integer is
  begin
    if i then
      return a;
    else
      return b;
    end if;
  end function;

  function if_else(i : boolean; a, b : std_ulogic) return std_ulogic is
  begin
    if i then
      return a;
    else
      return b;
    end if;
  end function;

  function if_else(i : boolean; a, b : std_ulogic_vector) return std_ulogic_vector is
  begin
    if i then
      return a;
    else
      return b;
    end if;
  end function;

  function if_else(i : boolean; a, b : std_logic_vector) return std_logic_vector is
  begin
    if i then
      return a;
    else
      return b;
    end if;
  end function;

  function if_else(i : boolean; a, b : unsigned) return unsigned is
  begin
    if i then
      return a;
    else
      return b;
    end if;
  end function;

end package body bool;
