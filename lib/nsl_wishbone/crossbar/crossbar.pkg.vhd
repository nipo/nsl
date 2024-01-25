library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math;
use work.wishbone.all;

package crossbar is

  -- Crossbar takes some bits from addresses masked with
  -- routing_mask_c and extracts them as a contiguous vector
  -- representing a number.  This number is then used as an index to
  -- the routing_table_c constant. If passed constant is too short for
  -- the index range, all undefined indices yield an error.
  --
  -- Example, with 32-bit addresses and routing_mask_c = x"80008000",
  -- there should be 4 entries in the table. If table contains (0, 2,
  -- 1, 1) and crossbar has 3 ports to slave, this yields the
  -- following accesses:
  -- - address = x"ffffc000", index = "11", port no = 1
  -- - address = x"00008f00", index = "01", port no = 2
  -- - address = x"00000000", index = "00", port no = 0
  -- - address = x"f0006000", index = "10", port no = 1
  component wishbone_crossbar is
    generic(
      wb_config_c : wb_config_t;
      slave_count_c : natural;
      routing_mask_c : unsigned;
      routing_table_c : nsl_math.int_ext.integer_vector
      );
    port(
      clock_i : std_ulogic;
      reset_n_i : std_ulogic;

      master_i : in wb_req_t;
      master_o : out wb_ack_t;

      slave_o : out wb_req_vector(0 to slave_count_c-1);
      slave_i : in wb_ack_vector(0 to slave_count_c-1)
      );
  end component;
  
end package crossbar;
