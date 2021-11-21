library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package serdes is

  type parity_t is (
    PARITY_NONE,
    PARITY_EVEN,
    PARITY_ODD
    );
  
  component uart_tx is
    generic(
      divisor_width : natural range 1 to 20;
      bit_count_c : natural;
      stop_count_c : natural range 1 to 2;
      parity_c : parity_t
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      divisor_i   : in unsigned(divisor_width-1 downto 0);
      
      uart_o      : out std_ulogic;

      data_i      : in std_ulogic_vector(bit_count_c-1 downto 0);
      ready_o     : out std_ulogic;
      valid_i     : in std_ulogic
      );
  end component;

  component uart_rx is
    generic(
      divisor_width : natural range 1 to 20;
      bit_count_c : natural;
      stop_count_c : natural range 1 to 2;
      parity_c : parity_t
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      divisor_i   : in unsigned(divisor_width-1 downto 0);
      
      uart_i      : in std_ulogic;

      data_o      : out std_ulogic_vector(bit_count_c-1 downto 0);
      valid_o     : out std_ulogic;
      ready_i     : in std_ulogic := '1';
      parity_ok_o : out std_ulogic;
      break_o     : out std_ulogic
      );
  end component;

end package serdes;
