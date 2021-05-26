library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_math, nsl_simulation, nsl_data;
use nsl_math.fixed.all;
use nsl_data.text.all;
use nsl_math.cordic.all;
use nsl_simulation.logging.all;

architecture arch of tb is

begin

  st: process
    variable angle_r, turns_r : real;
    variable turns_f : ufixed(-1 downto -20);
    variable x_f, y_f : sfixed(0 downto -20);
    variable x_r, y_r : real;
    variable max_error : real;
  begin
    for deg in 0 to 359
    loop
      angle_r := real(deg);
      turns_r := angle_r / 360.0;
      turns_f := to_ufixed(turns_r, turns_f'left, turns_f'right);

      sincos(turns_f, x_f, y_f);

      x_r := to_real(x_f);
      y_r := to_real(y_f);

      log_info(to_string(to_real(turns_f) * 360.0)
               & ";" & to_string(x_r)
               & ";" & to_string(y_r));

      max_error := realmax(abs(x_r - cos(turns_r * math_2_pi)), max_error);
      max_error := realmax(abs(y_r - sin(turns_r * math_2_pi)), max_error);
    end loop;

    log_info("Max error: " & to_string(max_error));
    log_info("Significant fractional bits: " & to_string(integer(floor(-log2(max_error)))));
    
    wait;
  end process;

end;
