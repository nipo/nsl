library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Intra-domain clocking utilities.
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

  -- Pipelined counter, with minimal timing requirements on
  -- inc_i. inc_i ends up being an enable signal to DFFs. Next value
  -- is itself pre-computed. This avoids having both the accumulator carry
  -- chain and the increment enable in the critical path.
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
    -- Next value lookahead
    next_o : out unsigned(width_c-1 downto 0);
    -- Whether value_o is matching max_c, i.e. next value is min_c
    wrap_o : out std_ulogic
    );
  end component;

end package intradomain;
