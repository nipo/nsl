library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_io, nsl_i2c;

-- Try to map to numbering defined in
-- https://digilent.com/reference/_media/reference/pmod/pmod-interface-specification-1_2_0.pdf,
package pmod is

  -- Looking into female header:
  -- Pin header:   6   5   4   3   2   1
  -- Pin no:       6   5   4   3   2   1 (Digilent numbering)
  -- Signal:     VCC GND IO4 IO3 IO2 IO1
  -- NSL:                (4) (3) (2) (1)
  subtype pmod_single_t is std_logic_vector(1 to 4);

  -- Looking into female header:
  -- Pin header:  12  10   8   6   4   2 (Usual 2.54 double row header)
  -- Pin header:  11   9   7   5   3   1 (Usual 2.54 double row header)
  -- Pin no:      12  11  10   9   8   7 (Digilent numbering)
  -- Pin no:       6   5   4   3   2   1 (Digilent numbering)
  -- Signal:     VCC GND IO8 IO7 IO6 IO5
  -- Signal:     VCC GND IO4 IO3 IO2 IO1
  -- NSL:                (8) (7) (6) (5)
  -- NSL:                (4) (3) (2) (1)
  subtype pmod_double_t is std_logic_vector(1 to 8);

end package pmod;
