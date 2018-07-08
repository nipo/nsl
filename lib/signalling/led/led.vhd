library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package led is

  type led_rgb8 is record
    r, g, b : std_ulogic_vector(7 downto 0);
  end record;

  type led_rgb8_vector is array(natural range <>) of led_rgb8;

  function "="(l, r : led_rgb8) return boolean;
  function "/="(l, r : led_rgb8) return boolean;
  function "="(l, r : led_rgb8_vector) return boolean;
  function "/="(l, r : led_rgb8_vector) return boolean;
  
end package led;
