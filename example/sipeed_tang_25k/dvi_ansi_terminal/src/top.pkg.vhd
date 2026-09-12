library ieee, nsl_dvi;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_digilent, nsl_usb;
use nsl_digilent.pmod.all;

package top is

  component main is
    generic (
      clock_i_hz_c : natural;
      mode_c : nsl_dvi.mode.mode_t
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      uart_i : in std_ulogic;
      uart_o : out std_ulogic;
      led_o: out std_ulogic_vector(0 to 1);

      usb_c_o : out nsl_usb.io.usb_io_c;
      usb_s_i : in nsl_usb.io.usb_io_s;

      pmod_dvi_o : out pmod_double_t
      );
  end component;



end package;
