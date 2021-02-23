library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package stream is

  type axis_16l_ms is
  record
    tdata  : std_ulogic_vector (15 downto 0);
    tvalid : std_ulogic;
    tlast  : std_ulogic;
  end record;

  type axis_16l_sm is
  record
    tready : std_ulogic;
  end record;

  type axis_16l_sm_vector is array(natural range <>) of axis_16l_sm;
  type axis_16l_ms_vector is array(natural range <>) of axis_16l_ms;

  type axis_16l is
  record
    m2s: axis_16l_ms;
    s2m: axis_16l_sm;
  end record;

  type axis_16l_vector is array(natural range <>) of axis_16l;

  type axis_8l_ms is
  record
    tdata  : std_ulogic_vector (7 downto 0);
    tvalid : std_ulogic;
    tlast  : std_ulogic;
  end record;

  type axis_8l_sm is
  record
    tready : std_ulogic;
  end record;

  type axis_8l_sm_vector is array(natural range <>) of axis_8l_sm;
  type axis_8l_ms_vector is array(natural range <>) of axis_8l_ms;

  type axis_8l is
  record
    m2s: axis_8l_ms;
    s2m: axis_8l_sm;
  end record;

  type axis_8l_vector is array(natural range <>) of axis_8l;

  component axis_8l_fifo is
    generic(
      word_count_c : natural;
      clock_count_c  : natural range 1 to 2;
      input_slice_c : boolean := false;
      output_slice_c : boolean := false;
      register_counters_c : boolean := false
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic_vector(0 to clock_count_c-1);

      in_i   : in axis_8l_ms;
      in_o   : out axis_8l_sm;
      free_o : out integer range 0 to word_count_c;

      out_i   : in axis_8l_sm;
      out_o   : out axis_8l_ms;
      available_o : out integer range 0 to word_count_c + 1
      );
  end component;

end package stream;
