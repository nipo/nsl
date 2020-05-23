library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sensor, nsl_clocking;
use nsl_sensor.stepper.all;

entity quadrature_decoder is
  generic (
    debounce_count_c : natural := 2
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    encoded_i     : in  std_ulogic_vector(0 to 1);
    step_o        : out step
    );
end entity;

architecture beh of quadrature_decoder is

  signal stable, rising, falling : std_ulogic_vector(0 to 1);
  
begin

  inputs: for i in 0 to 1
  generate
    filter: nsl_clocking.async.async_input
      generic map(
        debounce_count_c => debounce_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        data_i => encoded_i(i),
        data_o => stable(i),
        rising_o => rising(i),
        falling_o => falling(i)
        );
  end generate;

  output: process(stable, rising, falling)
  begin
    if (rising(0) = '1' and stable(1) = '0')
      or (falling(0) = '1' and stable(1) = '1')
      or (rising(1) = '1' and stable(0) = '1')
      or (falling(1) = '1' and stable(0) = '0') then
      step_o <= STEP_INCREMENT;
    elsif (falling(0) = '1' and stable(1) = '0')
      or (rising(0) = '1' and stable(1) = '1')
      or (falling(1) = '1' and stable(0) = '1')
      or (rising(1) = '1' and stable(0) = '0') then
      step_o <= STEP_DECREMENT;
    else
      step_o <= STEP_STABLE;
    end if;
  end process;

end architecture;
