library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package delay_line is

  component delay_line_memory is
    generic(
      data_width_c : integer;
      cycles_c : integer
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i : in  std_ulogic;

      ready_o : out std_ulogic;
      valid_i : in  std_ulogic;
      data_i : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  component delay_line_regs is
    generic(
      data_width_c : integer;
      cycles_c : integer
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i : in  std_ulogic;

      ready_o : out std_ulogic;
      valid_i : in  std_ulogic;
      data_i : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

end package delay_line;
