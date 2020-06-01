library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package lifo is

  type lifo_op_t is (
    LIFO_OP_IDLE,
    LIFO_OP_PUSH,
    LIFO_OP_POP
    );
  
  component lifo_regs
    generic(
      data_width_c : positive;
      word_count_c : positive
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      op_i : in lifo_op_t;
      data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o      : out std_ulogic_vector(data_width_c-1 downto 0);

      empty_o : out std_ulogic;
      full_o : out std_ulogic;
      free_o  : out integer range 0 to word_count_c;
      available_o : out integer range 0 to word_count_c
      );
  end component;
  
  component lifo_ram
    generic(
      data_width_c : positive;
      word_count_c : positive
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      op_i : in lifo_op_t;
      data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o      : out std_ulogic_vector(data_width_c-1 downto 0);

      empty_o : out std_ulogic;
      full_o : out std_ulogic;
      free_o  : out integer range 0 to word_count_c;
      available_o : out integer range 0 to word_count_c
      );
  end component;

end package lifo;
