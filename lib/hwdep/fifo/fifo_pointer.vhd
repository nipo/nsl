library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity fifo_pointer is
  generic(
    ptr_width         : natural;
    wrap_count        : integer;
    equal_can_move    : boolean; -- equal means empty, can move for wptr
    ptr_are_gray      : boolean
    );

  port(
    p_resetn : in std_ulogic;
    p_clk    : in std_ulogic;

    p_req : in  std_ulogic;
    p_ack : out std_ulogic;

    p_peer_ptr   : in  std_ulogic_vector(ptr_width downto 0);
    p_local_ptr  : out std_ulogic_vector(ptr_width downto 0);

    p_mem_ptr    : out unsigned(ptr_width-1 downto 0)
    );
end fifo_pointer;

architecture rtl of fifo_pointer is

  subtype ptr_t is unsigned(ptr_width-1 downto 0);
  constant c_idx_high : ptr_t := to_unsigned(wrap_count-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  
  type ctr_t is record
    wrap_toggle: std_logic;
    value: ptr_t;
  end record;

  type regs_t is record
    position: ctr_t;
    running: boolean;
  end record;

  signal s_can_inc, s_ptr_equal: boolean;
  signal s_local_ptr: std_ulogic_vector(ptr_width downto 0);
  signal r, rin: regs_t;

begin

  regs: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.position.value <= (others => '0');
      r.position.wrap_toggle <= '0';
      r.running <= false;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  local_ptr_pt: if not ptr_are_gray
  generate
    s_local_ptr(ptr_width) <= r.position.wrap_toggle;
    s_local_ptr(ptr_t'range) <= std_ulogic_vector(r.position.value);
  end generate;
  
  local_ptr_enc: if ptr_are_gray
  generate
    signal tmp : std_ulogic_vector(ptr_width downto 0);
  begin
    tmp <= r.position.wrap_toggle & std_ulogic_vector(r.position.value);

    enc: util.gray.gray_encoder
      generic map(
        data_width => ptr_width+1
        )
      port map(
        p_binary => tmp,
        p_gray => s_local_ptr
        );
  end generate;

  gray_cmp_gen: if ptr_are_gray
  generate
    signal a, b: std_ulogic_vector(ptr_width-1 downto 0);
  begin
    a(ptr_width-2 downto 0) <= s_local_ptr(ptr_width-2 downto 0);
    a(ptr_width-1) <= s_local_ptr(ptr_width-1) xor s_local_ptr(ptr_width);
    b(ptr_width-2 downto 0) <= p_peer_ptr(ptr_width-2 downto 0);
    b(ptr_width-1) <= p_peer_ptr(ptr_width-1) xor p_peer_ptr(ptr_width);

    s_ptr_equal <= a = b;
  end generate;

  bin_cmp_gen: if not ptr_are_gray
  generate
    s_ptr_equal <= s_local_ptr(ptr_t'range) = p_peer_ptr(ptr_t'range);
  end generate;
  
  s_can_inc <= not s_ptr_equal
    or (p_peer_ptr(ptr_width) = s_local_ptr(ptr_width)) = equal_can_move;

  p_ack <= '1' when r.running and s_can_inc else '0';
  p_local_ptr <= s_local_ptr;
  p_mem_ptr <= r.position.value;
  
  transition: process(r, p_req, s_can_inc)
  begin
    rin <= r;
    rin.running <= true;

    if r.running and s_can_inc and p_req = '1' then
      if c_is_pow2 then
        if r.position.value = c_idx_high then
          rin.position.wrap_toggle <= not r.position.wrap_toggle;
        end if;
        rin.position.value <= r.position.value + 1;
      else
        if r.position.value = c_idx_high then
          rin.position.wrap_toggle <= not r.position.wrap_toggle;
          rin.position.value <= (others => '0');
        else
          rin.position.value <= r.position.value + 1;
        end if;
      end if;
    end if;
  end process;
  
end rtl;
