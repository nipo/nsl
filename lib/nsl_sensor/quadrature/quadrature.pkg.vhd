library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sensor;

package quadrature is

  -- Quadrature decoder for linear and rotary encoders.
  -- Encoded input #0 is leading when incrementing:
  --                 
  --                      +------+      +------+
  --  encoded_i(0)        |      |      |      |
  --                 -----+      +------+      +------
  --
  --                 -+      +------+      +------+
  --  encoded_i(1)    |      |      |      |      |
  --                  +------+      +------+      +---
  --
  --                   incrementing   ------>
  component quadrature_decoder
    generic (
      debounce_count_c : natural := 2
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      encoded_i     : in  std_ulogic_vector(0 to 1);
      step_o        : out nsl_sensor.stepper.step
      );
  end component;

end package quadrature;
