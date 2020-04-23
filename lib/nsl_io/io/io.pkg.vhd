library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package io is

  type tristated is record
    v : std_ulogic;
    en : std_ulogic;
  end record;

  type directed is record
    v : std_ulogic;
    drive : std_ulogic;
  end record;

  type opendrain is record
    drain : std_ulogic;
  end record;

  component tristated_io_driver is
    port(
      v_i : in tristated;
      v_o : out std_ulogic;
      io_io : inout std_logic
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
