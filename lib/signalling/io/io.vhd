library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package io is

  type single is record
    v : std_ulogic;
  end record;

  type io_c is record
    v : std_ulogic;
    en : std_ulogic;
  end record;

  type io_s is record
    v : std_ulogic;
  end record;

  type directed_c is record
    v : std_ulogic;
    drive : std_ulogic;
  end record;

  type directed_s is record
    v : std_ulogic;
  end record;

  type od_c is record
    drain : std_ulogic;
  end record;

  type od_s is record
    v : std_ulogic;
  end record;

  component od_std_logic_driver is
    generic(
      hi_z : boolean := true
      );
    port(
      control : in od_c;
      status : out od_s;
      io : inout std_logic
      );
    end component;

  component io_std_logic_driver is
    port(
      control : in io_c;
      status : out io_s;
      io : inout std_logic
      );
    end component;

  component io_io_dir_driver is
    port(
      control : in io_c;
      status  : out io_s;
      io      : inout std_logic;
      dir_out : out std_ulogic
      );
    end component;

  component io_io_dir_in_driver is
    port(
      control : in io_c;
      status  : out io_s;
      i       : in std_ulogic;
      io      : inout std_logic;
      dir_out : out std_ulogic
      );
    end component;
  
end package io;
