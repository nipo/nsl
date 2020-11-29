library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_math;

entity fifo_pointer is
  generic(
    ptr_width_c         : natural;
    wrap_count_c        : integer;
    equal_can_move_c    : boolean; -- equal means empty, can move for wptr
    gray_position_c     : boolean;
    peer_ahead_c        : boolean
    );

  port(
    reset_n_i : in std_ulogic;
    clock_i    : in std_ulogic;

    inc_i : in  std_ulogic;
    ack_o : out std_ulogic;

    peer_position_i   : in  std_ulogic_vector(ptr_width_c downto 0);
    local_position_o  : out std_ulogic_vector(ptr_width_c downto 0);

    used_count_o : out unsigned(ptr_width_c downto 0);
    free_count_o : out unsigned(ptr_width_c downto 0);

    mem_ptr_o    : out unsigned(ptr_width_c-1 downto 0)
    );
end fifo_pointer;

-- "Position" is an aggregate of index (either gray or binary depending on
-- /gray_position_c/) on LSBs, and a "carry" bit (MSB) that toggles each time
-- the counter wraps. This allows to compare positions unambiguously for
-- empty/full conditions.

architecture rtl of fifo_pointer is

  subtype ptr_t is unsigned(ptr_width_c-1 downto 0);
  constant c_idx_high : ptr_t := to_unsigned(wrap_count_c-1, ptr_width_c);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');

  type regs_t is record
    wrap: std_ulogic;
    running: boolean;
  end record;

  signal r, rin: regs_t;
  signal s_can_inc, s_ptr_equal, s_in_same_wrap: boolean;
  signal s_counter, s_peer_counter : ptr_t;
  signal s_counter_wrap, s_peer_wrap, s_inc : std_ulogic;

begin

  counter: nsl_clocking.intradomain.intradomain_counter
    generic map(
      width_c => ptr_t'length,
      min_c => "0",
      max_c => c_idx_high,
      reset_c => "0"
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      increment_i => s_inc,
      value_o => s_counter,
      wrap_o => s_counter_wrap
      );
  
  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.wrap <= '0';
        r.running <= false;
      else
        r <= rin;
      end if;
    end if;
  end process;

  s_ptr_equal <= s_counter = s_peer_counter;
  s_in_same_wrap <= r.wrap = s_peer_wrap;
  s_can_inc <= r.running and (not s_ptr_equal or (s_in_same_wrap = equal_can_move_c));
  ack_o <= '1' when r.running and s_can_inc else '0';
  mem_ptr_o <= s_counter;
  s_inc <= inc_i when s_can_inc and r.running else '0';

  transition: process(r, s_counter_wrap, s_inc)
  begin
    rin <= r;

    rin.running <= true;

    if s_inc = '1' and s_counter_wrap = '1' then
      rin.wrap <= not r.wrap;
    end if;
  end process;

  gray_position: if gray_position_c
  generate
    signal peer_ptr_bin_relaxed : unsigned(ptr_width_c downto 0);
    signal local_ptr : unsigned(ptr_width_c downto 0);
  begin
    decoder: nsl_math.gray.gray_decoder_pipelined
      generic map(
        cycle_count_c => (ptr_width_c + 3) / 4,
        data_width_c => ptr_width_c + 1
        )
      port map(
        clock_i => clock_i,
        gray_i => peer_position_i,
        binary_o => peer_ptr_bin_relaxed
        );

    s_peer_wrap <= peer_ptr_bin_relaxed(peer_ptr_bin_relaxed'left);
    s_peer_counter <= peer_ptr_bin_relaxed(peer_ptr_bin_relaxed'left-1 downto 0);

    local_ptr(ptr_t'length) <= r.wrap;
    local_ptr(ptr_t'range) <= s_counter;

    gray_enc: process(clock_i)
    begin
      if rising_edge(clock_i) then
        local_position_o <= nsl_math.gray.bin_to_gray(local_ptr);
      end if;
    end process;
  end generate;

  bin_position: if not gray_position_c
  generate
    s_peer_wrap <= peer_position_i(ptr_t'length);
    s_peer_counter <= unsigned(peer_position_i(ptr_t'range));

    local_position_o(ptr_t'length) <= r.wrap;
    local_position_o(ptr_t'range) <= std_ulogic_vector(s_counter);
  end generate;

  free_calc: process(s_counter, s_peer_counter, s_in_same_wrap)
    variable head, tail, wrap_addedum, used, free : unsigned(ptr_width_c downto 0);
  begin
    wrap_addedum := to_unsigned(wrap_count_c, ptr_width_c + 1);

    -- When wrapping counter is the same, pointer difference is trivial
    -- When in different wrapping counts, we need to add up on complete cycle.
    -- Of course, this is easier for power-of-two wrap counts.
    if s_in_same_wrap then
      if peer_ahead_c then
        head := ("0" & s_counter);
        tail := ("0" & s_peer_counter);
      else
        head := ("0" & s_peer_counter);
        tail := ("0" & s_counter);
      end if;
    else
      if peer_ahead_c then
        -- Unsure whether optimizer sees this one, just in case, do it manually.
        if c_is_pow2 then
          head := ("1" & s_counter);
        else
          head := ("0" & s_counter) + wrap_addedum;
        end if;
        tail := ("0" & s_peer_counter);
      else
        if c_is_pow2 then
          head := ("1" & s_peer_counter);
        else
          head := ("0" & s_peer_counter) + wrap_addedum;
        end if;
        tail := ("0" & s_counter);
      end if;
    end if;

    used := head - tail;
    free := wrap_addedum + tail - head;

    -- Simulation hack:
    --
    -- Delta-cycles propagation may generate situations where the warning below
    -- happens (spurious warning).
    -- If we insert dontcares for such cases, synthesis tool should just delete
    -- the if condition and put the used/free count in all cases.
    -- Then this actually makes the thing work for simulation and synthesis cases.

    if to_integer(used) <= wrap_count_c then
      used_count_o <= used;
    else
      used_count_o <= (others => '-');
      --assert false
      --  report "Used pointer difference above wrap count: " & integer'image(to_integer(used))
      --  severity warning;
    end if;

    if to_integer(free) <= wrap_count_c then
      free_count_o <= free;
    else
      free_count_o <= (others => '-');
      --assert false
      --  report "Free pointer difference above wrap count: " & integer'image(to_integer(free))
      --  severity warning;
    end if;
  end process;

end rtl;
