library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.util.all;
use nsl.fifo.all;

entity sync_fifo is
  generic(
    data_width : integer;
    depth      : integer
    );
  port(
    p_resetn : in  std_ulogic;
    p_clk    : in  std_ulogic;

    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_read    : in  std_ulogic;
    p_out_empty_n : out std_ulogic;

    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_write  : in  std_ulogic;
    p_in_full_n : out std_ulogic
    );
end sync_fifo;

architecture rtl of sync_fifo is

  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type fifo_t is array(depth - 1 downto 0) of word_t;

  subtype count_t is unsigned(log2(depth)-1 downto 0);

  type regs_t is record
    usage : unsigned(log2(depth) downto 0);
    wptr  : count_t;
    rptr  : count_t;
  end record;

  signal r, rin : regs_t;
  
  signal r_mem  : fifo_t;

  signal s_full_n : std_ulogic;
  signal s_empty_n : std_ulogic;

  signal s_put : boolean;
  signal s_get : boolean;

begin

  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.usage <= (others => '0');
      r.wptr <= (others => '0');
      r.rptr <= (others => '0');
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process reg;

  s_full_n <= '0' when (r.usage = depth) else p_resetn;
  s_empty_n <= '0' when (r.usage = 0) else p_resetn;

  p_out_empty_n <= s_empty_n;
  p_in_full_n <= s_full_n;
  p_out_data <= r_mem(to_integer(r.rptr));

  ram_write: process (p_clk)
  begin
    if rising_edge(p_clk) then
      if s_full_n = '1' and p_in_write = '1' then
        r_mem(to_integer(r.wptr)) <= p_in_data;
      end if;
    end if;
  end process ram_write;

  put_get : process (p_out_read, r.usage, p_in_write)
  begin
    s_put <= false;
    s_get <= false;
    
    if r.usage = 0 then
      if p_in_write = '1' then
        s_put <= true;
      end if;
    elsif r.usage = depth then
      if p_out_read = '1' then
        s_get <= true;
      end if;
    else
      if p_in_write = '1' and p_out_read = '0' then
        s_put <= true;
      elsif p_in_write = '0' and p_out_read = '1' then
        s_get <= true;
      elsif p_in_write = '1' and p_out_read = '1' then
        s_put <= true;
        s_get <= true;
      end if;
    end if;
  end process;

  next_usage: process (s_get, s_put, r.usage)
  begin
    rin.usage <= r.usage;
    if s_get and not s_put then
      rin.usage <= r.usage - 1;
    elsif not s_get and s_put then
      rin.usage <= r.usage + 1;
    end if;
  end process next_usage;

  not_if_null: if depth > 1 generate
    
    next_rptr: process (s_get, r.rptr)
    begin
      rin.rptr <= r.rptr;
      if s_get then
        if r.rptr = depth - 1 then
          rin.rptr <= (others => '0');
        else
          rin.rptr <= r.rptr + 1;
        end if;
      end if;
    end process next_rptr;
    
    next_wptr: process (s_put, r.wptr)
    begin
      rin.wptr <= r.wptr;
      if s_put then
        if r.wptr = depth - 1 then
          rin.wptr <= (others => '0');
        else
          rin.wptr <= r.wptr + 1;
        end if;
      end if;
    end process next_wptr;
    
  end generate not_if_null;

  if_null: if depth <= 1 generate
    rin.rptr <= (others => '0');
    rin.wptr <= (others => '0');
  end generate if_null;
   
end rtl;
