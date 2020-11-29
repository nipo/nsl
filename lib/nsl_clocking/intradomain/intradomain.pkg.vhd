library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package intradomain is

  -- Basic multi-cycle synchronous register pipeline.  Mostly suited
  -- for retiming.
  component intradomain_multi_reg is
    generic(
      cycle_count_c : natural range 1 to 40 := 1;
      data_width_c : integer
      );
    port(
      clock_i : in std_ulogic;
      data_i  : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o  : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- Pipelined counter, with minimal timing requirements on inc_i.
  component intradomain_counter is
  generic(
    width_c : positive;

    min_c : unsigned;
    max_c : unsigned;
    reset_c : unsigned
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    increment_i : in std_ulogic;
    value_o  : out unsigned(width_c-1 downto 0);
    next_o : out unsigned(width_c-1 downto 0);
    -- Whether value_o is matching max_c, i.e. next value is min_c
    wrap_o : out std_ulogic
    );
  end component;

end package intradomain;
