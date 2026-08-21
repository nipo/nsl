library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_logic, nsl_math, nsl_memory;
use nsl_logic.bool.all;

entity fifo_homogeneous is
  generic(
    data_width_c   : integer;
    word_count_c        : integer;
    clock_count_c    : natural range 1 to 2;
    input_slice_c : boolean := false;
    output_slice_c : boolean := false;
    register_counters_c : boolean := false
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i    : in  std_ulogic_vector(0 to clock_count_c-1);

    out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i         : in  std_ulogic;
    out_valid_o         : out std_ulogic;
    out_available_min_o : out integer range 0 to word_count_c;
    out_available_o     : out integer range 0 to word_count_c + 1;

    in_data_i       : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i      : in  std_ulogic;
    in_ready_o      : out std_ulogic;
    in_free_o       : out integer range 0 to word_count_c
    );

end fifo_homogeneous;

-- Fifo backed by a dual-port memory holding one word per address.
--
-- Both sides run a binary counter that wraps at word_count_c, with an
-- extra bit toggling on every wrap. Comparing two such positions tells
-- apart the empty and the full case, and subtracting them yields a
-- word count without further state.
--
-- The input side counter addresses the memory write port and moves on
-- every accepted word. It stops when its position matches the peer
-- position on another wrap, which is the full condition.
--
-- Positions cross to the peer side through gray-coded pointer
-- synchronizers when each side has its own clock, through a couple of
-- registers otherwise. A received position is always late, never
-- early, so both sides err on the safe side: the input side sees at
-- most the room there is, the output side sees at most the words there
-- are.
--
-- The output side counter feeds addresses to a memory streamer, which
-- hides memory latency behind a prefetch and only issues reads it has
-- room to land. An address is issued for every position the input side
-- is known to have passed. The position that goes along with each
-- address travels through the streamer as sideband, so it comes back
-- aligned with its data word: the position of the word sitting at the
-- output port is known exactly, whatever the streamer holds behind it.
--
-- Fill level on the output side is the difference between the
-- resynchronized input position and the position of that word. Because
-- positions carry the wrap bit, this counts the words still in memory,
-- the words held in the prefetch and the one in the output register
-- alike, with no correction term. That same position is what crosses
-- back to the input side, so a memory word only frees its address once
-- it left the output port. The fifo therefore holds exactly
-- word_count_c words, wherever they sit, and both fill counts are
-- exact for the peer position each side sees.
architecture ram2 of fifo_homogeneous is

  constant ptr_width_c: natural := nsl_math.arith.log2(word_count_c);
  subtype mem_ptr_t is unsigned(ptr_width_c-1 downto 0);
  -- Memory index on the LSBs, wrap bit on the MSB.
  subtype position_t is unsigned(ptr_width_c downto 0);
  subtype data_t is std_ulogic_vector(data_width_c-1 downto 0);

  constant last_index_c: mem_ptr_t := to_unsigned(word_count_c-1, ptr_width_c);
  constant is_pow2_c: boolean := last_index_c = (last_index_c'range => '1');
  constant is_synchronous_c: boolean := clock_count_c = 1;

  function position_next(position: position_t) return position_t is
    variable ret: position_t;
  begin
    if position(mem_ptr_t'range) = last_index_c then
      ret := (not position(position_t'left)) & to_unsigned(0, ptr_width_c);
    else
      ret := position(position_t'left) & (position(mem_ptr_t'range) + 1);
    end if;
    return ret;
  end function;

  -- Word count from tail (included) to head (excluded). Both positions
  -- must come from the same counter, head being the one ahead. A pair
  -- that does not compare yields /disjoint/ instead, and every caller
  -- passes the count that promises nothing: this happens while the two
  -- sides are not out of reset together, where announcing a wrong
  -- count would be worse than announcing an empty fifo on one side and
  -- a full one on the other.
  function position_diff(head, tail: position_t; disjoint: natural) return natural is
    constant h: position_t := to_01(head);
    constant t: position_t := to_01(tail);
    variable count: unsigned(ptr_width_c downto 0);
  begin
    count := ("0" & h(mem_ptr_t'range)) - ("0" & t(mem_ptr_t'range));
    if h(position_t'left) /= t(position_t'left) then
      count := count + to_unsigned(word_count_c, count'length);
    end if;

    if to_integer(count) > word_count_c then
      return disjoint;
    end if;

    return to_integer(count);
  end function;

  signal reset_n_s: std_ulogic_vector(0 to clock_count_c-1);

  signal in_data_s: data_t;
  signal in_valid_s, in_ready_s: std_ulogic;
  signal out_data_s: data_t;
  signal out_valid_s, out_ready_s: std_ulogic;

  -- Input side, in clock_i(0)
  type in_regs_t is
  record
    running: boolean;
    position: position_t;
  end record;

  signal in_r, in_rin: in_regs_t;

  -- Output side, in clock_i(clock_count_c-1)
  type out_regs_t is
  record
    -- Next position to hand over to the streamer.
    read: position_t;
    -- Position of the next word to leave the streamer.
    output: position_t;
  end record;

  signal out_r, out_rin: out_regs_t;

  -- Input side position, and the same after crossing to the output side.
  signal in_position_s, in_position_resync_s: position_t;
  -- Output side position, and the same after crossing to the input side.
  signal out_position_s, out_position_resync_s: position_t;

  -- Input side sees the memory as full, output side sees it as empty.
  signal in_full_s, out_empty_s: boolean;

  signal mem_write_en_s: std_ulogic;
  signal mem_write_address_s: mem_ptr_t;
  signal mem_read_en_s: std_ulogic;
  signal mem_read_address_s: mem_ptr_t;
  signal mem_read_data_s: data_t;

  signal addr_valid_s, addr_ready_s: std_ulogic;
  signal addr_s: mem_ptr_t;
  signal sideband_in_s, sideband_out_s: std_ulogic_vector(position_t'length-1 downto 0);

  signal available_s, available_min_s, free_s: integer range 0 to word_count_c;

begin

  assert is_synchronous_c or is_pow2_c
    report "Bisynchronous fifos can only work for power-of-two depths"
    severity failure;

  with_input_slice: if input_slice_c
  generate
    input_slice: nsl_memory.fifo.fifo_register_slice
      generic map(
        data_width_c => data_width_c
        )
      port map(
        clock_i => clock_i(0),
        reset_n_i => reset_n_s(0),

        out_data_o => in_data_s,
        out_ready_i => in_ready_s,
        out_valid_o => in_valid_s,

        in_data_i => in_data_i,
        in_valid_i => in_valid_i,
        in_ready_o => in_ready_o
        );
  end generate;

  without_input_slice: if not input_slice_c
  generate
    in_data_s <= in_data_i;
    in_valid_s <= in_valid_i;
    in_ready_o <= in_ready_s;
  end generate;

  with_output_slice: if output_slice_c
  generate
    output_slice: nsl_memory.fifo.fifo_register_slice
      generic map(
        data_width_c => data_width_c
        )
      port map(
        clock_i => clock_i(clock_count_c-1),
        reset_n_i => reset_n_s(clock_count_c-1),

        out_data_o => out_data_o,
        out_ready_i => out_ready_i,
        out_valid_o => out_valid_o,

        in_data_i => out_data_s,
        in_valid_i => out_valid_s,
        in_ready_o => out_ready_s
        );
  end generate;

  without_output_slice: if not output_slice_c
  generate
    out_data_o <= out_data_s;
    out_valid_o <= out_valid_s;
    out_ready_s <= out_ready_i;
  end generate;

  async: if not is_synchronous_c generate
    reset_sync: nsl_clocking.async.async_multi_reset
      generic map(
        debounce_count_c => 4,
        domain_count_c => 2
        )
      port map(
        clock_i => clock_i,
        master_i => reset_n_i,
        slave_o => reset_n_s
        );

    in_to_out: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => position_t'length,
        decode_stage_count_c => (position_t'length + 3) / 4
        )
      port map(
        clock_in_i => clock_i(0),
        clock_out_i => clock_i(clock_count_c-1),
        data_i => in_position_s,
        data_o => in_position_resync_s
        );

    out_to_in: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => position_t'length,
        decode_stage_count_c => (position_t'length + 3) / 4
        )
      port map(
        clock_in_i => clock_i(clock_count_c-1),
        clock_out_i => clock_i(0),
        data_i => out_position_s,
        data_o => out_position_resync_s
        );
  end generate;

  sync: if is_synchronous_c generate
    reset_n_s(0) <= reset_n_i;

    -- Only insert a 2-cycle delay, enough to keep the memory ahead of
    -- the reader and to leave both position paths registered.

    in_to_out: nsl_clocking.intradomain.intradomain_multi_reg
      generic map(
        data_width_c => position_t'length
        )
      port map(
        clock_i => clock_i(0),
        data_i => std_ulogic_vector(in_position_s),
        unsigned(data_o) => in_position_resync_s
        );

    out_to_in: nsl_clocking.intradomain.intradomain_multi_reg
      generic map(
        data_width_c => position_t'length
        )
      port map(
        clock_i => clock_i(0),
        data_i => std_ulogic_vector(out_position_s),
        unsigned(data_o) => out_position_resync_s
        );
  end generate;

  in_regs: process(clock_i(0), reset_n_s(0)) is
  begin
    if rising_edge(clock_i(0)) then
      in_r <= in_rin;
    end if;

    if reset_n_s(0) = '0' then
      in_r.running <= false;
      in_r.position <= (others => '0');
    end if;
  end process;

  -- Same index on another wrap means the input side caught up with the
  -- output side from behind.
  in_full_s <= in_r.position(mem_ptr_t'range) = out_position_resync_s(mem_ptr_t'range)
               and in_r.position(position_t'left) /= out_position_resync_s(position_t'left);

  in_transition: process(in_r, in_valid_s, in_full_s) is
  begin
    in_rin <= in_r;

    in_rin.running <= true;

    if in_r.running and in_valid_s = '1' and not in_full_s then
      in_rin.position <= position_next(in_r.position);
    end if;
  end process;

  in_moore: process(in_r, in_valid_s, in_full_s, out_position_resync_s) is
  begin
    -- Peer position is only meaningful once out of reset, hold the
    -- input side back until then rather than acknowledge a word the
    -- position counter would not account for.
    in_ready_s <= to_logic(in_r.running and not in_full_s);
    mem_write_en_s <= to_logic(in_r.running and not in_full_s) and in_valid_s;
    mem_write_address_s <= in_r.position(mem_ptr_t'range);
    free_s <= word_count_c
              - position_diff(in_r.position, out_position_resync_s, word_count_c);
    in_position_s <= in_r.position;
  end process;

  ram: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => data_t'length,
      clock_count_c => clock_count_c
      )
    port map(
      clock_i => clock_i,

      write_address_i => mem_write_address_s,
      write_en_i => mem_write_en_s,
      write_data_i => in_data_s,

      read_address_i => mem_read_address_s,
      read_en_i => mem_read_en_s,
      read_data_o => mem_read_data_s
      );

  out_regs: process(clock_i(clock_count_c-1), reset_n_s(clock_count_c-1)) is
  begin
    if rising_edge(clock_i(clock_count_c-1)) then
      out_r <= out_rin;
    end if;

    if reset_n_s(clock_count_c-1) = '0' then
      out_r.read <= (others => '0');
      out_r.output <= (others => '0');
    end if;
  end process;

  -- Nothing left to read as long as the output side did not see the
  -- input side move past its own position.
  out_empty_s <= out_r.read = in_position_resync_s;

  out_transition: process(out_r, out_empty_s, addr_ready_s,
                          out_valid_s, out_ready_s, sideband_out_s) is
  begin
    out_rin <= out_r;

    if not out_empty_s and addr_ready_s = '1' then
      out_rin.read <= position_next(out_r.read);
    end if;

    -- The word leaving the output port carries the position it was
    -- read from, next one to leave is the one after it.
    if out_valid_s = '1' and out_ready_s = '1' then
      out_rin.output <= position_next(unsigned(sideband_out_s));
    end if;
  end process;

  out_moore: process(out_r, out_empty_s, in_position_resync_s, out_valid_s) is
    variable available: integer range 0 to word_count_c;
  begin
    available := position_diff(in_position_resync_s, out_r.output, 0);

    addr_valid_s <= to_logic(not out_empty_s);
    addr_s <= out_r.read(mem_ptr_t'range);
    sideband_in_s <= std_ulogic_vector(out_r.read);
    out_position_s <= out_r.output;

    available_s <= available;
    if out_valid_s = '1' and available /= 0 then
      available_min_s <= available - 1;
    else
      available_min_s <= available;
    end if;
  end process;

  reader: nsl_memory.streamer.memory_streamer
    generic map(
      addr_width_c => mem_ptr_t'length,
      data_width_c => data_t'length,
      memory_latency_c => 1,
      sideband_width_c => position_t'length
      )
    port map(
      clock_i => clock_i(clock_count_c-1),
      reset_n_i => reset_n_s(clock_count_c-1),

      addr_valid_i => addr_valid_s,
      addr_ready_o => addr_ready_s,
      addr_i => addr_s,
      sideband_i => sideband_in_s,

      data_valid_o => out_valid_s,
      data_ready_i => out_ready_s,
      data_o => out_data_s,
      sideband_o => sideband_out_s,

      mem_enable_o => mem_read_en_s,
      mem_address_o => mem_read_address_s,
      mem_sideband_o => open,
      mem_data_i => mem_read_data_s
      );

  registered_counters: if register_counters_c
  generate
    in_counter: process(clock_i(0)) is
    begin
      if rising_edge(clock_i(0)) then
        in_free_o <= free_s;
      end if;
    end process;

    out_counter: process(clock_i(clock_count_c-1)) is
    begin
      if rising_edge(clock_i(clock_count_c-1)) then
        out_available_min_o <= available_min_s;
        out_available_o <= available_s;
      end if;
    end process;
  end generate;

  non_registered_counters: if not register_counters_c
  generate
    in_free_o <= free_s;
    out_available_min_o <= available_min_s;
    out_available_o <= available_s;
  end generate;

end ram2;
