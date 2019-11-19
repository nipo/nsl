library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package fifo is

  component fifo_2p
    generic(
      data_width   : integer;
      depth        : integer;
      clk_count    : natural range 1 to 2
      );
    port(
      reset_n_i   : in  std_ulogic;
      clk_i       : in  std_ulogic_vector(0 to clk_count-1);

      out_data_o          : out std_ulogic_vector(data_width-1 downto 0);
      out_ready_i         : in  std_ulogic;
      out_valid_o         : out std_ulogic;
      -- Pessimistic fill count as seen from the output side. This counter may
      -- never reach actual fill count of fifo.
      out_available_min_o : out integer range 0 to depth;
      -- Corrected fill count as seen from the output side. This
      -- counter eventually reaches actual fill count of fifo, but
      -- takes more resources to calculate.  Actual fill count may be
      -- depth + 1 because of the output register of backing RAM
      -- block.
      out_available_o     : out integer range 0 to depth+1;

      in_data_i  : in  std_ulogic_vector(data_width-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;
      -- Pessimistic availability count as seen from the input
      -- side. This counter may never reach actual free count of fifo.
      in_free_o  : out integer range 0 to depth
      );
  end component;

  component fifo_pointer is
    generic(
      ptr_width         : natural;
      wrap_count        : integer;
      equal_can_move    : boolean; -- equal means empty, can move for wptr
      gray_position     : boolean;
      peer_ahead        : boolean;
      increment_early   : boolean := false
      );
    port(
      reset_n_i        : in  std_ulogic;
      clk_i            : in  std_ulogic;
      inc_i            : in  std_ulogic;
      ack_o            : out std_ulogic;
      peer_position_i  : in  std_ulogic_vector(ptr_width downto 0);
      local_position_o : out std_ulogic_vector(ptr_width downto 0);
      used_count_o     : out unsigned(ptr_width downto 0);
      free_count_o     : out unsigned(ptr_width downto 0);
      mem_ptr_o        : out unsigned(ptr_width-1 downto 0)
      );
  end component;

end package fifo;
