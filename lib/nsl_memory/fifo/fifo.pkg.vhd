library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwconfig;

package fifo is

  -- What fifo_auto has to provide. Build it with fifo_config().
  type fifo_config_t is
  record
    data_width: natural;
    word_count: positive;
    clock_count: natural range 1 to 2;
    -- Register slices on the ports, see fifo_homogeneous.
    input_slice: boolean;
    output_slice: boolean;
    -- Fill counters are meaningful. Only then, register_counters
    -- matters.
    counters: boolean;
    register_counters: boolean;
    -- Commit/rollback on either side, see fifo_homogeneous.
    in_cancellable: boolean;
    out_cancellable: boolean;
  end record;

  function fifo_config(
    data_width: natural;
    word_count: positive;
    clock_count: natural range 1 to 2 := 1;
    input_slice: boolean := false;
    output_slice: boolean := false;
    counters: boolean := false;
    register_counters: boolean := false;
    in_cancellable: boolean := false;
    out_cancellable: boolean := false) return fifo_config_t;

  type fifo_implementation_t is (
    FIFO_IMPLEMENTATION_SHIFT_REGISTER,
    FIFO_IMPLEMENTATION_LUTRAM,
    FIFO_IMPLEMENTATION_HOMOGENEOUS,
    FIFO_IMPLEMENTATION_REGISTER_SLICE
    );

  -- Data bits (word_count * data_width) up to which fifo_auto keeps
  -- words in fifo_shift_register rather than in memory, depending on
  -- whether the target has LUT RAM. Shift register cost grows with
  -- stored bits, the other ones mostly have a fixed cost: LUT RAM
  -- primitives are 64 bits large, and fifo_homogeneous carries a few
  -- words of prefetch registers and control logic beside its memory.
  constant fifo_auto_shift_register_bits_lutram_c: natural := 16;
  constant fifo_auto_shift_register_bits_no_lutram_c: natural := 64;

  -- Implementation fifo_auto selects for a configuration on a target
  -- with given LUT RAM resources, first matching rule wins:
  --
  -- 1. register slice if word_count is at most 2 and neither counters
  --    nor cancellation are requested: fifo_register_slice with one
  --    clock, fifo_register_slice followed by
  --    nsl_clocking.interdomain.interdomain_fifo_slice with two;
  --
  -- 2. fifo_homogeneous if clock_count is 2, or if counters or
  --    cancellation on either side are requested: no other block has
  --    them. These need word_count above 2;
  --
  -- 3. fifo_shift_register if word_count is at most 16 and
  --    word_count * data_width is at most
  --    fifo_auto_shift_register_bits_lutram_c (target with LUT RAM)
  --    or fifo_auto_shift_register_bits_no_lutram_c (target without);
  --
  -- 4. fifo_lutram if the target has LUT RAM with asynchronous read
  --    and word_count is at most its fifo_depth_max;
  --
  -- 5. fifo_homogeneous otherwise, for block RAM.
  function fifo_auto_implementation(
    config: fifo_config_t;
    lutram: nsl_hwconfig.memory_config.lutram_t) return fifo_implementation_t;

  -- Fifo whose implementation is picked at elaboration,
  -- by fifo_auto_implementation() against the LUT RAM resources of the
  -- target (nsl_hwconfig.memory_config), as the cheapest block that
  -- provides everything config_c asks for. Features that are not asked
  -- for cost nothing.
  --
  -- Ports and their meaning are the ones of fifo_homogeneous.
  -- Whatever the implementation:
  --
  -- - words come out in the order they went in, none is lost or
  --   duplicated;
  --
  -- - capacity is at least word_count, exactly word_count without
  --   slices, each slice adding up to two words. A register slice
  --   implementation (word_count of 1 or 2) holds two words with one
  --   clock, three with two, and has registered ports already: slices
  --   asked for add nothing to it;
  --
  -- - a word is presented on the output at least one cycle after it
  --   was accepted.
  --
  -- Latency and exact ready/valid timing differ between
  -- implementations, hence between targets. Designs may only rely on
  -- the handshake. In particular, simulation without a target vendor
  -- selects as a typical target with LUT RAM does, see
  -- nsl_hwconfig.memory_config.
  --
  -- Counter outputs are only meaningful when config_c.counters is set.
  -- Commit and rollback inputs are ignored on a side that is not
  -- cancellable. Counters and cancellation need word_count above 2,
  -- elaboration fails otherwise.
  component fifo_auto is
    generic(
      config_c: fifo_config_t
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic_vector(0 to config_c.clock_count-1);

      out_data_o: out std_ulogic_vector(config_c.data_width-1 downto 0);
      out_ready_i: in std_ulogic;
      out_valid_o: out std_ulogic;
      out_commit_i: in std_ulogic := '1';
      out_rollback_i: in std_ulogic := '0';
      out_available_min_o: out integer range 0 to config_c.word_count;
      out_available_o: out integer range 0 to config_c.word_count+1;

      in_data_i: in std_ulogic_vector(config_c.data_width-1 downto 0);
      in_valid_i: in std_ulogic;
      in_ready_o: out std_ulogic;
      in_commit_i: in std_ulogic := '1';
      in_rollback_i: in std_ulogic := '0';
      in_free_o: out integer range 0 to config_c.word_count
      );
  end component;

  -- Fifo backed by a dual-port memory, with an optional second clock
  -- domain on the output side.
  --
  -- New code should use fifo_auto, which falls back to this one only
  -- for what cheaper blocks cannot do.
  --
  -- Either side may be made cancellable through its *_cancellable_c
  -- generic. A cancellable side hands its beats over speculatively:
  -- the peer only gets to see them, and the fifo only gets to reuse
  -- their storage, once commit is asserted; rollback takes all
  -- uncommitted beats back.
  --
  -- Commit and rollback are symmetric in time: both apply to every
  -- beat accepted up to and including the cycle they are asserted
  -- on. Asserting commit along with the last beat of a packet commits
  -- that beat too, asserting rollback along with a beat cancels that
  -- beat too. Neither needs a beat to be flowing.
  --
  -- Asserting commit and rollback on the same cycle is a usage error,
  -- and simulation fails on it.
  --
  -- Rollback on the output side takes the port down for the cycle it
  -- is asserted on: out_valid_o falls as soon as out_rollback_i rises,
  -- and the words come again on the cycles after it.
  --
  -- On a side that is not cancellable, commit and rollback inputs are
  -- ignored, every beat is committed as it is accepted.
  --
  -- A cancellable side may not be sliced: a word held in a register
  -- slice cannot be taken back.
  component fifo_homogeneous
    generic(
      data_width_c   : integer;
      word_count_c        : integer;
      clock_count_c    : natural range 1 to 2;
      input_slice_c : boolean := false;
      output_slice_c : boolean := false;
      register_counters_c : boolean := false;
      in_cancellable_c : boolean := false;
      out_cancellable_c : boolean := false
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i       : in  std_ulogic_vector(0 to clock_count_c-1);

      out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
      out_ready_i         : in  std_ulogic;
      out_valid_o         : out std_ulogic;
      -- Marks every word taken from the port so far as delivered.
      -- Their memory space is released to the input side.
      out_commit_i        : in  std_ulogic := '1';
      -- Takes back every word taken from the port since the last
      -- commit. They are handed over again, in order, starting from
      -- the committed position.
      out_rollback_i      : in  std_ulogic := '0';
      -- Fill count as seen from the output side, minus the word
      -- currently presented on the port, if any.
      out_available_min_o : out integer range 0 to word_count_c;
      -- Count of words the input side committed and the output port
      -- did not hand over yet: exact for the input position the
      -- output side knows of, hence never overstated, and reaching
      -- the actual fill count when input traffic pauses. Words a
      -- rollback would hand over again are not counted, so this only
      -- counts what a reader that never rolls back will see. Total
      -- capacity is word_count_c, wherever the words sit.
      out_available_o     : out integer range 0 to word_count_c+1;

      in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;
      -- Marks every word given to the port so far as written. The
      -- output side gets to see them.
      in_commit_i : in  std_ulogic := '1';
      -- Takes back every word given to the port since the last
      -- commit. Their memory space is reused by the words to come.
      in_rollback_i : in  std_ulogic := '0';
      -- Free capacity as seen from the input side, with speculative
      -- words counted as used: exact for the output position it knows
      -- of, hence never overstated, and reaching the actual free
      -- capacity when output traffic pauses. Nonzero if and only if
      -- in_ready_o is asserted. Note that a packet longer than
      -- word_count_c can never be written, as an uncommitted packet
      -- holds its own space.
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

  -- Shallow FIFO made of shifting registers steered by a one-hot fill
  -- register. Cheapest for one or two words, or for a few narrow
  -- words, at the price of moving every stored word on each pop. For
  -- anything wider or deeper, see fifo_lutram, or let fifo_auto
  -- choose.
  --
  -- Handshake is fully registered: in_ready_o and out_valid_o only
  -- depend on internal state, there is no combinational path between
  -- the input and the output port. A word pushed on a cycle is
  -- presented on the next one. A full fifo refuses a push even when a
  -- pop takes place on the same cycle.
  component fifo_shift_register is
    generic(
      data_width_c: natural;
      word_count_c: natural range 1 to 16
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      in_data_i: in std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i: in std_ulogic;
      in_ready_o: out std_ulogic;

      out_data_o: out std_ulogic_vector(data_width_c-1 downto 0);
      out_valid_o: out std_ulogic;
      out_ready_i: in std_ulogic;

      -- Registered one-hot fill level. fill_o(k) is set when the FIFO
      -- holds k words. Test single bits of it instead of comparing a
      -- count.
      fill_o: out std_ulogic_vector(0 to word_count_c)
      );
  end component;

  -- Single-clock FIFO over a memory array written synchronously and
  -- read asynchronously, which synthesizers map to LUT RAM where the
  -- target has some, to registers and a read multiplexer otherwise.
  -- Any depth, a power of two saves a comparison per index.
  --
  -- Same port contract as fifo_shift_register, cycle for cycle:
  -- in_ready_o and out_valid_o are registered, a word pushed on a
  -- cycle is presented on the next one, a full fifo refuses a push
  -- even when a pop takes place on the same cycle. out_data_o is the
  -- head word read from the array with no clock edge in between: it
  -- goes through the LUT RAM read path, not straight out of a
  -- register.
  component fifo_lutram is
    generic(
      data_width_c: natural;
      word_count_c: positive
      );
    port(
      reset_n_i: in std_ulogic;
      clock_i: in std_ulogic;

      in_data_i: in std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i: in std_ulogic;
      in_ready_o: out std_ulogic;

      out_data_o: out std_ulogic_vector(data_width_c-1 downto 0);
      out_valid_o: out std_ulogic;
      out_ready_i: in std_ulogic;

      -- Registered one-hot fill level. fill_o(k) is set when the FIFO
      -- holds k words. Costs word_count_c+1 registers if connected,
      -- nothing if left open.
      fill_o: out std_ulogic_vector(0 to word_count_c)
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
  -- Deprecated, superseded by fifo_homogeneous with in_cancellable_c
  -- and out_cancellable_c. Note commit takes the beats accepted
  -- strictly before its own cycle there, where fifo_homogeneous takes
  -- the beat of the commit cycle as well.
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

  -- A fifo that only counts for valid/ready. This is like a fifo with 0-bit
  -- data words
  component fifo_count
    generic(
      max_count_l2_c : natural;
      clock_count_c : natural range 1 to 2
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic_vector(0 to clock_count_c-1);

      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic;
      out_counter_o : out unsigned(max_count_l2_c-1 downto 0);

      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;
      in_counter_o : out unsigned(max_count_l2_c-1 downto 0)
      );
  end component;

end package fifo;

package body fifo is

  function fifo_config(
    data_width: natural;
    word_count: positive;
    clock_count: natural range 1 to 2 := 1;
    input_slice: boolean := false;
    output_slice: boolean := false;
    counters: boolean := false;
    register_counters: boolean := false;
    in_cancellable: boolean := false;
    out_cancellable: boolean := false) return fifo_config_t
  is
  begin
    return fifo_config_t'(
      data_width => data_width,
      word_count => word_count,
      clock_count => clock_count,
      input_slice => input_slice,
      output_slice => output_slice,
      counters => counters,
      register_counters => register_counters,
      in_cancellable => in_cancellable,
      out_cancellable => out_cancellable);
  end function;

  function fifo_auto_implementation(
    config: fifo_config_t;
    lutram: nsl_hwconfig.memory_config.lutram_t) return fifo_implementation_t
  is
    variable shift_register_bits: natural;
  begin
    if config.word_count <= 2
      and not config.counters
      and not config.in_cancellable
      and not config.out_cancellable then
      return FIFO_IMPLEMENTATION_REGISTER_SLICE;
    end if;

    if config.clock_count /= 1
      or config.counters
      or config.in_cancellable
      or config.out_cancellable then
      return FIFO_IMPLEMENTATION_HOMOGENEOUS;
    end if;

    if lutram.present then
      shift_register_bits := fifo_auto_shift_register_bits_lutram_c;
    else
      shift_register_bits := fifo_auto_shift_register_bits_no_lutram_c;
    end if;

    if config.word_count <= 16
      and config.word_count * config.data_width <= shift_register_bits then
      return FIFO_IMPLEMENTATION_SHIFT_REGISTER;
    end if;

    if lutram.present
      and lutram.async_read
      and config.word_count <= lutram.fifo_depth_max then
      return FIFO_IMPLEMENTATION_LUTRAM;
    end if;

    return FIFO_IMPLEMENTATION_HOMOGENEOUS;
  end function;

end package body fifo;
