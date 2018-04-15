library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity fifo_write_pointer is
  generic(
    ptr_width : natural;
    wrap_count: integer
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_valid    : in  std_ulogic;
    p_ready    : out std_ulogic;

    p_peer_ptr : in  unsigned(ptr_width-1 downto 0);
    p_mem_ptr  : out unsigned(ptr_width-1 downto 0);
    p_write    : out std_ulogic
    );
end fifo_write_pointer;

architecture rtl of fifo_write_pointer is

  subtype ptr_t is unsigned(ptr_width-1 downto 0);
  constant c_idx_high : ptr_t := to_unsigned(wrap_count-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  
  type regs_t is record
    running: boolean;
    moved_before_equal: boolean;
    ptr: ptr_t;
  end record;

  signal r, rin: regs_t;

  function ptr_inc(x: ptr_t) return ptr_t is
  begin
    if c_is_pow2 or x /= c_idx_high then
      return x + 1;
    else
      return (others => '0');
    end if;
  end function ptr_inc;

  signal s_can_take: boolean;

begin

  regs: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.running <= false;
      r.ptr <= (others => '0');
      r.moved_before_equal <= false;
    elsif rising_edge(p_clk) then
      r <= rin;
      r.running <= true;
    end if;
  end process;

  s_can_take <= r.running and (p_peer_ptr /= r.ptr or not r.moved_before_equal);
  p_ready <= '1' when s_can_take else '0';
  p_write <= p_valid when s_can_take else '0';
  p_mem_ptr <= r.ptr;
  
  transition: process(r, p_valid, p_peer_ptr, s_can_take)
  begin
    rin <= r;

    if r.running then
      if p_valid = '1' and s_can_take then
        rin.ptr <= ptr_inc(r.ptr);
        rin.moved_before_equal <= true;
      elsif p_peer_ptr /= r.ptr then
        rin.moved_before_equal <= false;
      end if;
    end if;
  end process;

end rtl;
