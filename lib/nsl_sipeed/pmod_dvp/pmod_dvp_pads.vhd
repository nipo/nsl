library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_i2c, nsl_io, nsl_clocking;

entity pmod_dvp_pads is
  generic(
    pclk_buffer_mode_c: string := "global"
    );
  port(
    control_io: inout nsl_digilent.pmod.pmod_double_t;
    data_io: inout nsl_digilent.pmod.pmod_double_t;

    xclk_i: in std_ulogic;

    i2c_i: in nsl_i2c.i2c.i2c_o;
    i2c_o: out nsl_i2c.i2c.i2c_i;

    sensor_reset_n_i: in std_ulogic;
    sensor_power_down_i: in std_ulogic;

    pclk_o: out std_ulogic;
    vsync_o: out std_ulogic;
    href_o: out std_ulogic;
    data_o: out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture beh of pmod_dvp_pads is

  signal control_s: nsl_io.io.tristated_vector(1 to 8);
  signal control_in_s, data_in_s: std_ulogic_vector(1 to 8);

begin

  control_s(1) <= nsl_io.io.to_tristated(i2c_i.sda);
  control_s(2) <= nsl_io.io.to_tristated('0', not sensor_reset_n_i);
  control_s(3) <= nsl_io.io.to_tristated('0', not sensor_power_down_i);
  control_s(4) <= nsl_io.io.to_tristated('0', '0');
  control_s(5) <= nsl_io.io.to_tristated(i2c_i.scl);
  control_s(6) <= nsl_io.io.to_tristated('0', '0');
  control_s(7) <= nsl_io.io.to_tristated('0', '0');
  control_s(8) <= nsl_io.io.to_tristated(xclk_i, '1');

  control_pad: for i in control_s'range
  generate
    pad: nsl_io.io.tristated_io_driver
      port map(
        v_i => control_s(i),
        v_o => control_in_s(i),
        io_io => control_io(i)
        );
  end generate;

  data_io <= (others => 'Z');
  data_in_s <= std_ulogic_vector(data_io);

  i2c_o.sda <= control_in_s(1);
  i2c_o.scl <= control_in_s(5);

  vsync_o <= control_in_s(6);
  href_o <= control_in_s(7);
  data_o <= control_in_s(4) & data_in_s(1) & data_in_s(5) & data_in_s(6)
            & data_in_s(7) & data_in_s(8) & data_in_s(4) & data_in_s(3);

  pclk_buffer: nsl_clocking.distribution.clock_buffer
    generic map(
      mode_c => pclk_buffer_mode_c
      )
    port map(
      clock_i => data_in_s(2),
      clock_o => pclk_o
      );

end architecture;
