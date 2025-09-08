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
  -- Pin header:  11   9   7   5   3   1 (Usual 2.54 double row header)
  -- Pin header:  12  10   8   6   4   2 (Usual 2.54 double row header)
  -- Pin no:       6   5   4   3   2   1 (Digilent numbering)
  -- Pin no:      12  11  10   9   8   7 (Digilent numbering)
  -- Signal:     VCC GND IO8 IO7 IO6 IO5
  -- Signal:     VCC GND IO4 IO3 IO2 IO1
  -- NSL:                (4) (3) (2) (1)
  -- NSL:                (8) (7) (6) (5)
  subtype pmod_double_t is std_logic_vector(1 to 8);

  -- SPI master mapping Type2
  component pmod_type2_driver is
    port(
      pmod_io: inout pmod_single_t;
      spi_i: in nsl_spi.spi.spi_master_o;
      spi_o: out nsl_spi.spi.spi_master_i
      );
  end component;

  -- SPI master mapping Type2a
  component pmod_type2a_driver is
    port(
      pmod_io: inout pmod_double_t;
      spi_i: in nsl_spi.spi.spi_master_o;
      spi_o: out nsl_spi.spi.spi_master_i;
      cs_n_i: in nsl_io.io.opendrain_vector(2 to 3);
      reset_i: in nsl_io.io.opendrain;
      int_o: out std_ulogic
      );
  end component;

  -- I2C master mapping Type6
  component pmod_type6_driver is
    port(
      pmod_io: inout pmod_single_t;
      i2c_i: in nsl_i2c.i2c.i2c_o;
      i2c_o: out nsl_i2c.i2c.i2c_i;
      reset_i: in nsl_io.io.opendrain;
      int_o: out std_ulogic
      );
  end component;

end package pmod;
