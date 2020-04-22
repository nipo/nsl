library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fifo is

  component fifo_homogeneous
    generic(
      data_width_c   : integer;
      word_count_c        : integer;
      clock_count_c    : natural range 1 to 2
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i       : in  std_ulogic_vector(0 to clock_count-1);

      out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
      out_ready_i         : in  std_ulogic;
      out_valid_o         : out std_ulogic;
      -- Pessimistic fill count as seen from the output side. This counter may
      -- never reach actual fill count of fifo.
      out_available_min_o : out integer range 0 to word_count_c;
      -- Corrected fill count as seen from the output side. This
      -- counter eventually reaches actual fill count of fifo, but
      -- takes more resources to calculate.  Actual fill count may be
      -- word_count_c + 1 because of the output register of backing RAM
      -- block.
      out_available_o     : out integer range 0 to word_count_c+1;

      in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;
      -- Pessimistic availability count as seen from the input
      -- side. This counter may never reach actual free count of fifo.
      in_free_o  : out integer range 0 to word_count_c
      );
  end component;

  component fifo_pointer is
    generic(
      ptr_width_c         : natural;
      wrap_count_c        : integer;
      equal_can_move_c    : boolean; -- equal means empty, can move for wptr
      gray_position_c     : boolean;
      peer_ahead_c        : boolean
      );
    port(
      reset_n_i        : in  std_ulogic;
      clock_i            : in  std_ulogic;
      inc_i            : in  std_ulogic;
      ack_o            : out std_ulogic;
      peer_position_i  : in  std_ulogic_vector(ptr_width_c downto 0);
      local_position_o : out std_ulogic_vector(ptr_width_c downto 0);
      used_count_o     : out unsigned(ptr_width_c downto 0);
      free_count_o     : out unsigned(ptr_width_c downto 0);
      mem_ptr_o        : out unsigned(ptr_width_c-1 downto 0)
      );
  end component;

end package fifo;
