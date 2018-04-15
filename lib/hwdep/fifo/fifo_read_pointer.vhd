library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity fifo_read_pointer is
  generic(
    ptr_width : natural;
    wrap_count: integer
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_valid    : out std_ulogic;
    p_ready    : in  std_ulogic;

    p_peer_ptr : in  unsigned(ptr_width-1 downto 0);
    p_mem_ptr  : out unsigned(ptr_width-1 downto 0);
    p_read     : out std_ulogic
    );
end fifo_read_pointer;

architecture rtl of fifo_read_pointer is

  subtype ptr_t is unsigned(ptr_width-1 downto 0);
  constant c_idx_high : ptr_t := to_unsigned(wrap_count-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  
  type regs_t is record
    moved_before_equal: boolean;
    data_valid: boolean;
    read_addr: ptr_t;
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

  signal s_has_more_data: boolean;
  
begin

  regs: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.read_addr <= (others => '0');
      r.moved_before_equal <= false;
      r.data_valid <= false;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  p_valid <= '1' when r.data_valid else '0';
  p_read <= p_ready when r.data_valid else '1';
  p_mem_ptr <= r.read_addr;
  s_has_more_data <= p_peer_ptr /= r.read_addr or not r.moved_before_equal;

  transition: process(r, p_ready, p_peer_ptr, s_has_more_data)
  begin
    rin <= r;
    
    if (r.data_valid and p_ready = '1') or not r.data_valid then
      rin.data_valid <= s_has_more_data;
      if s_has_more_data then
        rin.read_addr <= ptr_inc(r.read_addr);
        rin.moved_before_equal <= true;
      end if;
    elsif p_peer_ptr /= r.read_addr then
      rin.moved_before_equal <= false;
    end if;
  end process;

end rtl;
