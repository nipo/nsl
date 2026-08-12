library ieee;
use ieee.std_logic_1164.all;

-- Gearbox components for bit-width conversion
package gearbox is

  -- Constant-to-variable width gearbox
  --
  -- Accepts fixed-width input and produces variable-width output.
  -- Input is loaded when in_ready_o is high (input must be valid).
  -- Output always has valid data after initialization warmup.
  -- Each cycle, out_len_i bits are consumed from the output.
  --
  -- Bit ordering is left-to-right (index 0 is first/leftmost bit).
  --
  -- Constraint: input_width_c >= output_max_width_c
  component gearbox_c2v is
    generic(
      input_width_c      : positive;
      output_max_width_c : positive
      );
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      in_i       : in  std_ulogic_vector(0 to input_width_c - 1);
      in_ready_o : out std_ulogic;

      out_len_i  : in  integer range 0 to output_max_width_c;
      out_o      : out std_ulogic_vector(0 to output_max_width_c - 1)
      );
  end component;

  -- Variable-to-constant width gearbox
  --
  -- Accepts variable-width input and produces fixed-width output.
  -- in_len_i specifies how many bits from in_i are valid this cycle.
  -- Output is valid when out_valid_o is high (consumer must accept).
  --
  -- Bit ordering is left-to-right (index 0 is first/leftmost bit).
  component gearbox_v2c is
    generic(
      input_max_width_c : positive;
      output_width_c    : positive
      );
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      in_i       : in  std_ulogic_vector(0 to input_max_width_c - 1);
      in_len_i   : in  integer range 0 to input_max_width_c;

      out_valid_o : out std_ulogic;
      out_o       : out std_ulogic_vector(0 to output_width_c - 1)
      );
  end component;

  -- Constant-to-constant width gearbox
  --
  -- Accepts fixed-width input and produces fixed-width output.
  -- input_width_c must be two times the size of output_width_c or
  -- vice versa. clock_i must be faster by an even multiple than the clock
  -- used in the data domain which is larger
  --
  -- Example: 16 bits in, 8 bits out, clock_i at 125MHz and new
  -- 16 bit value every clock cycle at 62.5MHz (Gigabit ethernet).
  -- In this case the input is sampled twice every cycle as seen
  -- from the 62.5MHz clock. 
  --
  component gearbox_c2c is
    generic(
      input_width_c : positive;
      output_width_c    : positive;
      msb_first_c : boolean := false      
      );
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      in_i       : in  std_ulogic_vector(0 to input_width_c - 1);
      ready_o   : out std_ulogic;      

      out_o       : out std_ulogic_vector(0 to output_width_c - 1);
      valid_o   : out std_ulogic      
      );
  end component;  

end package gearbox;
