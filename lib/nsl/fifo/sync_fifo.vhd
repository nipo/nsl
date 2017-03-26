library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.util.all;

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

  signal r_usage, s_usage : count_t;
  signal r_wptr, s_wptr   : count_t;
  signal r_rptr, s_rptr   : count_t;
  
  signal r_mem  : fifo_t;

  signal s_full_n : std_ulogic;
  signal s_empty_n : std_ulogic;

  signal s_put : boolean;
  signal s_get : boolean;

begin

  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r_usage <= (others => '0');
      r_wptr <= (others => '0');
      r_rptr <= (others => '0');
    elsif rising_edge(p_clk) then
      r_usage <= s_usage;
      r_wptr <= s_wptr;
      r_rptr <= s_rptr;
    end if;
  end process reg;

  s_full_n <= '0' when (r_usage = depth) else p_resetn;
  s_empty_n <= '0' when (r_usage = 0) else p_resetn;

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_out_empty_n <= s_empty_n;
      p_in_full_n <= s_full_n;
      p_out_data <= r_mem(to_integer(r_rptr));
    end if;
  end process;

  ram_write: process (p_clk)
  begin
    if rising_edge(p_clk) then
      if s_full_n = '1' and p_in_write = '1' then
        r_mem(to_integer(r_wptr)) <= p_in_data;
      end if;
    end if;
  end process ram_write;

  put_get : process (p_out_read, r_usage, p_in_write)
  begin
    s_put <= false;
    s_get <= false;
    
    if r_usage = 0 then                                -- empty
      if p_in_write = '1' then
        s_put <= true;
      end if;
    elsif r_usage = depth then                    -- full
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

  next_usage: process (s_get, s_put, r_usage)
  begin
    s_usage <= r_usage;
    if s_get and not s_put then
      s_usage <= r_usage - 1;
    elsif not s_get and s_put then
      s_usage <= r_usage + 1;
    end if;
  end process next_usage;

  not_if_null: if depth > 1 generate
    
    next_rptr: process (s_get, r_rptr)
    begin
      s_rptr <= r_rptr;
      if s_get then
        if r_rptr = depth - 1 then
          s_rptr <= (others => '0');
        else
          s_rptr <= r_rptr + 1;
        end if;
      end if;
    end process next_rptr;
    
    next_wptr: process (s_put, r_wptr)
    begin
      s_wptr <= r_wptr;
      if s_put then
        if r_wptr = depth - 1 then
          s_wptr <= (others => '0');
        else
          s_wptr <= r_wptr + 1;
        end if;
      end if;
    end process next_wptr;
    
  end generate not_if_null;

  if_null: if depth <= 1 generate
    
    s_rptr <= (others => '0');
    s_wptr <= (others => '0');
    
  end generate if_null;
   
end rtl;
