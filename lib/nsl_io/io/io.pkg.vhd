library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package io is

  type tristated is record
    v : std_ulogic;
    en : std_ulogic;
  end record;

  type tristated_vector is array (natural range <>) of tristated;

  type directed is record
    v : std_ulogic;
    output : std_ulogic;
  end record;

  type directed_vector is array (natural range <>) of directed;
  
  type opendrain is record
    -- Whether not to drain the wire.
    -- Value of drain_n matches expected wire value.
    drain_n : std_ulogic;
  end record;

  type opendrain_vector is array (natural range <>) of opendrain;

  function "+"(x, y : opendrain) return opendrain;
  function to_tristated(x : opendrain) return tristated;
  function to_tristated(x : directed) return tristated;
  function to_tristated(v : std_ulogic; en : std_ulogic := '1') return tristated;
  function to_tristated(v : std_ulogic; en : boolean) return tristated;
  function to_directed(x : opendrain) return directed;
  function to_directed(x : tristated) return directed;
  function to_directed(v : std_ulogic; output : std_ulogic := '1') return directed;
  function to_directed(v : std_ulogic; output : boolean) return directed;
  function to_logic(x : opendrain) return std_logic;
  function to_logic(x : directed) return std_logic;
  function to_logic(x : tristated) return std_logic;
  function to_logic(v : std_ulogic; en : std_ulogic := '1') return std_logic;

  constant tristated_z : tristated := (en => '0', v => '-');
  constant directed_z : directed := (output => '0', v => '-');
  constant opendrain_z : opendrain := (drain_n => '1');
  
  component tristated_io_driver is
    port(
      v_i : in tristated;
      v_o : out std_ulogic;
      io_io : inout std_logic
      );
    end component;
  
  component tristated_vector_io_driver is
    generic(
      width_c : natural
      );
    port(
      v_i : in tristated_vector(width_c-1 downto 0);
      v_o : out std_ulogic_vector(width_c-1 downto 0);
      io_io : inout std_logic_vector(width_c-1 downto 0)
      );
    end component;

  component opendrain_io_driver is
    port(
      v_i : in opendrain;
      v_o : out std_ulogic;
      io_io : inout std_logic
      );
    end component;

  component directed_io_driver is
    port(
      v_i : in directed;
      v_o : out std_ulogic;
      io_io : inout std_logic
      );
    end component;

  component directed_io_driver_gated is
    generic(
      gate_output_value_c : std_ulogic
      );
    port(
      v_i : in directed;
      v_o : out std_ulogic;
      io_o : inout std_logic;
      gate_dir_o : out std_ulogic
      );
    end component;
  
end package io;

package body io is

  function "+"(x, y : opendrain) return opendrain is
    variable z : opendrain;
  begin
    z.drain_n := x.drain_n and y.drain_n;

    return z;
  end function;

  function to_tristated(x : opendrain) return tristated is
    variable z : tristated;
  begin
    z.v := '0';
    z.en := not x.drain_n;

    return z;
  end function;

  function to_tristated(x : directed) return tristated is
    variable r : tristated;
  begin
    r.v := x.v;
    r.en := x.output;
    return r;
  end function;

  function to_tristated(v : std_ulogic; en : std_ulogic := '1') return tristated is
    variable r : tristated;
  begin
    r.v := v;
    r.en := en;
    return r;
  end function;

  function to_directed(x : opendrain) return directed
  is
  begin
    return directed'(output => not x.drain_n, v => '0');
  end function;
  
  function to_directed(x : tristated) return directed
  is
  begin
    return directed'(output => x.en, v => x.v);
  end function;
  
  function to_directed(v : std_ulogic; output : std_ulogic := '1') return directed
  is
  begin
    return directed'(output => output, v => v);
  end function;

  function to_logic(x : opendrain) return std_logic
  is
  begin
    if x.drain_n = '0' then
      return '0';
    else
      return 'Z';
    end if;
  end function;

  function to_logic(x : tristated) return std_logic
  is
  begin
    if x.en = '1' then
      return x.v;
    else
      return 'Z';
    end if;
  end function;

  function to_logic(x : directed) return std_logic
  is
  begin
    if x.output = '1' then
      return x.v;
    else
      return 'Z';
    end if;
  end function;

  function to_logic(v : std_ulogic; en : std_ulogic := '1') return std_logic
  is
  begin
    if en = '1' then
      return v;
    else
      return 'Z';
    end if;
  end function;

  function to_tristated(v : std_ulogic; en : boolean) return tristated
  is
  begin
    if en then
      return tristated'(v => v, en => '1');
    else
      return tristated'(v => '-', en => '0');
    end if;
  end function;

  function to_directed(v : std_ulogic; output : boolean) return directed
  is
  begin
    if output then
      return directed'(v => v, output => '1');
    else
      return directed'(v => '-', output => '0');
    end if;
  end function;

end package body io;
