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

  type opendrain is record
    -- Whether not to drain the wire.
    -- Value of drain_n matches expected wire value.
    drain_n : std_ulogic;
  end record;

  function "+"(x, y : opendrain) return opendrain;
  function to_tristated(x : opendrain) return tristated;
  
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

end package body io;
