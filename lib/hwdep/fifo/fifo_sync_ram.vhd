library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.util.all;

library hwdep;
use hwdep.ram.all;

entity fifo_sync is
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
end fifo_sync;

architecture soft of fifo_sync is

  type state is (
    GOING_EMPTY,
    GOING_FULL
    );
  
  constant count_width : integer := log2(depth);
  subtype count_t is std_ulogic_vector(count_width-1 downto 0);
  subtype count_u is unsigned(count_width-1 downto 0);
  
  signal r_in_wptr_bin, r_out_rptr_bin: count_u := (others => '0');
  signal s_in_wptr_bin, s_out_rptr_bin: count_u := (others => '0');
  signal r_state: state := GOING_EMPTY;

  signal s_going_full, s_going_empty: std_ulogic;
  signal s_ptr_equal: boolean;
  
  signal r_in_full, r_out_empty : std_ulogic;
  signal s_in_write, s_out_read : std_ulogic;

begin

  s_out_rptr_bin <= r_out_rptr_bin + 1 when s_out_read = '1'
                    else r_out_rptr_bin;

  s_in_wptr_bin <= r_in_wptr_bin + 1 when s_in_write = '1'
                 else r_in_wptr_bin;

  ptr: process(p_clk, p_resetn, s_in_write)
  begin
    if p_resetn = '0' then
      r_in_wptr_bin <= (others => '0');
      r_out_rptr_bin <= (others => '0');
    elsif rising_edge(p_clk) then
      r_in_wptr_bin <= s_in_wptr_bin;
      r_out_rptr_bin <= s_out_rptr_bin;
    end if;
  end process ptr;

  ram: hwdep.ram.ram_2p
    generic map(
      addr_size => count_width,
      data_size => data_width,
      passthrough_12 => true
      )
    port map(
      p_clk1 => p_clk,
      p_addr1 => std_ulogic_vector(r_in_wptr_bin),
      p_wren1 => s_in_write,
      p_wdata1 => p_in_data,
      p_rdata1 => open,

      p_clk2 => p_clk,
      p_addr2 => std_ulogic_vector(s_out_rptr_bin),
      p_wren2 => '0',
      p_wdata2 => (others => 'X'),
      p_rdata2 => p_out_data
      );

  s_out_read <= p_out_read and not r_out_empty;
  s_in_write <= p_in_write and not r_in_full;

  process(p_clk, p_in_write, p_out_read)
  begin
    if rising_edge(p_clk) then
      s_going_full <= p_in_write and not p_out_read;
      s_going_empty <= not p_in_write and p_out_read;
    end if;
  end process;
  
  
  process(s_going_full, s_going_empty, p_resetn)
  begin
    if s_going_empty = '1' or p_resetn = '0' then
      r_state <= GOING_EMPTY;
    elsif s_going_full = '1' then
      r_state <= GOING_FULL;
    end if;
  end process;

  s_ptr_equal <= s_in_wptr_bin = s_out_rptr_bin;
  
  process(p_clk, r_state, s_ptr_equal)
  begin
    if r_state = GOING_FULL and s_ptr_equal then
      r_in_full <= '1';
    elsif rising_edge(p_clk) then
      r_in_full <= '0';
    end if;

    if r_state = GOING_EMPTY and s_ptr_equal then
      r_out_empty <= '1';
    elsif rising_edge(p_clk) then
      r_out_empty <= '0';
    end if;
  end process;

  p_in_full_n <= not r_in_full;
  p_out_empty_n <= not r_out_empty;
   
end soft;
