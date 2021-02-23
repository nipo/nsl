library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fifo is

  component fifo_homogeneous
    generic(
      data_width_c   : integer;
      word_count_c        : integer;
      clock_count_c    : natural range 1 to 2;
      input_slice_c : boolean := false;
      output_slice_c : boolean := false;
      register_counters_c : boolean := false
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i       : in  std_ulogic_vector(0 to clock_count_c-1);

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

  -- Basic register slice. Decouples timing constraints between input and
  -- output port. This is actually a 2-depth fifo.
  component fifo_register_slice is
    generic(
      data_width_c : integer
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      out_data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic;

      in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic
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

  component fifo_narrower
    generic(
      part_count_c : integer;
      out_width_c : integer
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      out_data_o  : out std_ulogic_vector(out_width_c-1 downto 0);
      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic;

      in_data_i  : in  std_ulogic_vector(part_count_c*out_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic
      );
  end component;

  component fifo_widener
    generic(
      part_count_c    : integer;
      in_width_c : integer
      );
    port(
      reset_n_i : in std_ulogic;
      clk_i     : in std_ulogic;

      out_data_o  : out std_ulogic_vector(part_count_c*in_width_c-1 downto 0);
      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic;

      in_data_i  : in  std_ulogic_vector(in_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic
      );
  end component;

  -- This component has two sets of read/write pointers, one actual set, and
  -- one speculative set. Reads and writes can be cancelled / committed and
  -- replayed ad libitum.
  --
  -- If data is flowing at the same time commit or rollback are asserted,
  -- whether data that flowed at the exact same cycle is committed/rolled back
  -- is undefined.
  --
  -- If commit/rollback is not used for one of the ports, just leave
  -- assignments to their default values. Data will always end up to
  -- be committed.
  --
  -- When issuing rollback, port may not be ready the next cycle. Handshaking
  -- will be correct, though.
  component fifo_cancellable
    generic(
      data_width_c    : integer;
      word_count_l2_c : integer
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i       : in  std_ulogic;

      out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
      out_ready_i         : in  std_ulogic;
      out_valid_o         : out std_ulogic;
      -- When asserted, commits the buffer as taken, and moves the actual
      -- read pointer to current speculative position.
      out_commit_i : in std_ulogic := '1';
      -- When asserted, read data since last commit is assumed to be lost and
      -- read pointer is rolled back to last read position.
      out_rollback_i : in std_ulogic := '0';
      -- Reflects actual availability in *committed* space. This does not take
      -- into account speculative read/writes to the fifo.
      out_available_o : out unsigned(word_count_l2_c downto 0);

      in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;
      in_commit_i : in std_ulogic := '1';
      in_rollback_i : in std_ulogic := '0';
      -- Reflects actual free space in *committed* space. This does not take
      -- into account speculative read/writes to the fifo.
      in_free_o : out unsigned(word_count_l2_c downto 0)
      );
  end component;

end package fifo;
