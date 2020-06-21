library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package stepper is

  type step is (
    STEP_STABLE,
    STEP_INCREMENT,
    STEP_DECREMENT
    );

  component step_divisor is
    generic (
      divisor_c : natural := 2
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      step_i        : in step;
      step_o        : out step
      );
  end component;

  component step_accumulator is
    generic (
      counter_width_c : natural;
      allow_wrap_c : boolean := false
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      step_i        : in step;
      low_i         : in std_ulogic := '0';
      low_value_i   : in unsigned(counter_width_c-1 downto 0) := (others => '0');
      high_i        : in std_ulogic := '0';
      high_value_i  : in unsigned(counter_width_c-1 downto 0) := (others => '1');
      value_o       : out unsigned(counter_width_c-1 downto 0)
      );
  end component;
  
end package stepper;
