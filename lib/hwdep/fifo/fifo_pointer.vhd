library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity fifo_pointer is
  generic(
    ptr_width         : natural;
    wrap_count        : integer;
    equal_can_move    : boolean; -- equal means empty, can move for wptr
    gray_position     : boolean;
    peer_ahead        : boolean;
    increment_early   : boolean := false
    );

  port(
    reset_n_i : in std_ulogic;
    clk_i    : in std_ulogic;

    inc_i : in  std_ulogic;
    ack_o : out std_ulogic;

    peer_position_i   : in  std_ulogic_vector(ptr_width downto 0);
    local_position_o  : out std_ulogic_vector(ptr_width downto 0);

    used_count_o : out unsigned(ptr_width downto 0);
    free_count_o : out unsigned(ptr_width downto 0);

    mem_ptr_o    : out unsigned(ptr_width-1 downto 0)
    );
end fifo_pointer;

-- "Position" is an aggregate of index (either gray or binary depending on
-- /gray_position/) on LSBs, and a "carry" bit (MSB) that toggles once
-- every two wrapping. This allows to compare positions unambiguously for
-- empty/full conditions.

architecture rtl of fifo_pointer is

  subtype ptr_t is unsigned(ptr_width-1 downto 0);
  constant c_idx_high : ptr_t := to_unsigned(wrap_count-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');

  type ctr_t is record
    wrap_toggle: std_logic;
    value: ptr_t;
  end record;

  type regs_t is record
    wcounter: ctr_t;
    running: boolean;
  end record;

  signal s_can_inc, s_ptr_equal: boolean;
  signal s_local_position: std_ulogic_vector(ptr_width downto 0);
  signal s_local_ptr: std_ulogic_vector(ptr_width downto 0);
  signal r, rin: regs_t;

  signal peer_wcounter : ctr_t;

  function next_ctr(cur: ctr_t) return ctr_t is
    variable ret : ctr_t;
  begin
    ret := cur;

    if c_is_pow2 then
      if cur.value = c_idx_high then
        ret.wrap_toggle := not cur.wrap_toggle;
      end if;
      ret.value := cur.value + 1;
    else
      if cur.value = c_idx_high then
        ret.wrap_toggle := not cur.wrap_toggle;
        ret.value := (others => '0');
      else
        ret.value := cur.value + 1;
      end if;
    end if;
    return ret;

  end function;

begin

  regs: process (clk_i, reset_n_i)
  begin
    if rising_edge(clk_i) then
      if reset_n_i = '0' then
        r.wcounter.value <= (others => '0');
        r.wcounter.wrap_toggle <= '0';
        r.running <= false;
      else
        r <= rin;
      end if;
    end if;
  end process;

  s_local_ptr <= r.wcounter.wrap_toggle & std_ulogic_vector(r.wcounter.value);

  local_ptr_bin: if not gray_position
  generate
    s_local_position <= s_local_ptr;

    s_ptr_equal <= s_local_position(ptr_t'range) = peer_position_i(ptr_t'range);
  end generate;

  local_ptr_gray: if gray_position
  generate
    signal a, b: std_ulogic_vector(ptr_width-1 downto 0);
  begin
    s_local_position <= util.gray.bin_to_gray(unsigned(s_local_ptr));
    a(ptr_width-2 downto 0) <= s_local_position(ptr_width-2 downto 0);
    a(ptr_width-1) <= s_local_position(ptr_width-1) xor s_local_position(ptr_width);
    b(ptr_width-2 downto 0) <= peer_position_i(ptr_width-2 downto 0);
    b(ptr_width-1) <= peer_position_i(ptr_width-1) xor peer_position_i(ptr_width);

    s_ptr_equal <= a = b;
  end generate;

  s_can_inc <= not s_ptr_equal
    or (peer_position_i(ptr_width) = s_local_position(ptr_width)) = equal_can_move;

  ack_o <= '1' when r.running and s_can_inc else '0';
  local_position_o <= s_local_position;
  mem_ptr_o <= r.wcounter.value;

  transition: process(r, inc_i, s_can_inc)
  begin
    rin <= r;
    rin.running <= true;

    if r.running and s_can_inc and inc_i = '1' then
      rin.wcounter <= next_ctr(r.wcounter);
    end if;
  end process;

  decode_position: if gray_position
  generate
    signal peer_ptr_bin : std_ulogic_vector(ptr_width downto 0);
    signal peer_ptr_bin_relaxed : std_ulogic_vector(ptr_width downto 0);
  begin
    peer_ptr_bin <= std_ulogic_vector(util.gray.gray_to_bin(peer_position_i));

    decoder_pipeline: util.sync.sync_multi_reg
      generic map(
        cycle_count => (ptr_width + 3) / 4,
        data_width => ptr_width+1
        )
      port map(
        p_clk => clk_i,
        p_in => peer_ptr_bin,
        p_out => peer_ptr_bin_relaxed
        );
    peer_wcounter.wrap_toggle <= peer_ptr_bin_relaxed(peer_ptr_bin_relaxed'left);
    peer_wcounter.value <= unsigned(peer_ptr_bin_relaxed(peer_ptr_bin_relaxed'left-1 downto 0));
  end generate;

  forward_position: if not gray_position
  generate
    peer_wcounter.wrap_toggle <= peer_position_i(ptr_t'length);
    peer_wcounter.value <= unsigned(peer_position_i(ptr_t'range));
  end generate;

  -- peer_wcounter holds same data as r.wcounter:
  -- - a toggle of wraps
  -- - an index

  calc: process(r.wcounter, peer_wcounter)
    variable head, tail, wrap, used, free : unsigned(ptr_width downto 0);
  begin
    wrap := to_unsigned(wrap_count, ptr_width + 1);

    -- When wrapping counter is the same, pointer difference is trivial
    -- When in different wrapping counts, we need to add up on complete cycle.
    -- Of course, this is easier for power-of-two wrap counts.
    if r.wcounter.wrap_toggle = peer_wcounter.wrap_toggle then
      if peer_ahead then
        head := ("0" & r.wcounter.value);
        tail := ("0" & peer_wcounter.value);
      else
        head := ("0" & peer_wcounter.value);
        tail := ("0" & r.wcounter.value);
      end if;
    else
      if peer_ahead then
        -- Unsure whether optimizer sees this one, just in case, do it manually.
        if c_is_pow2 then
          head := ("1" & r.wcounter.value);
        else
          head := ("0" & r.wcounter.value) + wrap;
        end if;
        tail := ("0" & peer_wcounter.value);
      else
        if c_is_pow2 then
          head := ("1" & peer_wcounter.value);
        else
          head := ("0" & peer_wcounter.value) + wrap;
        end if;
        tail := ("0" & r.wcounter.value);
      end if;
    end if;

    used := head - tail;
    free := wrap + tail - head;

    -- Simulation hack:
    --
    -- Delta-cycles propagation may generate situations where the warning below
    -- happens (spurious warning).
    -- If we insert dontcares for such cases, synthesis tool should just delete
    -- the if condition and put the used/free count in all cases.
    -- Then this actually makes the thing work for simulation and synthesis cases.

    if to_integer(used) <= wrap_count then
      used_count_o <= used;
    else
      used_count_o <= (others => '-');
      --assert false
      --  report "Used pointer difference above wrap count: " & integer'image(to_integer(used))
      --  severity warning;
    end if;

    if to_integer(free) <= wrap_count then
      free_count_o <= free;
    else
      free_count_o <= (others => '-');
      --assert false
      --  report "Free pointer difference above wrap count: " & integer'image(to_integer(free))
      --  severity warning;
    end if;
  end process;

end rtl;
