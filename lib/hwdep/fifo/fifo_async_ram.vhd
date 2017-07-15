library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.util.all;

library hwdep;
use hwdep.ram.all;

entity fifo_async is
  generic(
    data_width : integer;
    depth      : integer
    );
  port(
    p_resetn   : in  std_ulogic;

    p_out_clk     : in  std_ulogic;
    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_read    : in  std_ulogic;
    p_out_empty_n : out std_ulogic;

    p_in_clk    : in  std_ulogic;
    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_write  : in  std_ulogic;
    p_in_full_n : out std_ulogic
    );
end fifo_async;

architecture ram of fifo_async is

  type state is (
    GOING_EMPTY,
    GOING_FULL
    );
  
  constant count_width : integer := log2(depth);
  subtype count_t is std_ulogic_vector(count_width-1 downto 0);
  subtype count_u is unsigned(count_width-1 downto 0);
  
  signal s_common_rst : std_ulogic;
  signal s_rst: std_ulogic_vector(1 downto 0);
  signal s_out_resetn, s_in_resetn : std_ulogic;

  signal r_in_wptr_bin, r_out_rptr_bin: count_u;
  signal s_in_wptr_bin, s_out_rptr_bin: count_u;
  signal r_state: state;

  signal s_in_wptr_gray, s_out_rptr_gray: count_t;

  signal s_going_full, s_going_empty: std_ulogic;
  signal s_ptr_equal: boolean;
  
  signal r_in_full, r_out_empty : std_ulogic;
  signal s_in_write, s_out_read : std_ulogic;

begin

  reset_sync_out: nsl.util.reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_clk => p_out_clk,
      p_resetn_sync => s_rst(1)
      );

  reset_sync_in: nsl.util.reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_clk => p_in_clk,
      p_resetn_sync => s_rst(0)
      );

  s_common_rst <= s_rst(0) and s_rst(1);
  
  reset_sync_out_in: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_common_rst,
      p_clk => p_in_clk,
      p_resetn_sync => s_in_resetn
      );

  reset_sync_in_out: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_common_rst,
      p_clk => p_out_clk,
      p_resetn_sync => s_out_resetn
      );

  s_out_rptr_bin <= r_out_rptr_bin + 1 when s_out_read = '1'
                    else r_out_rptr_bin;

  s_in_wptr_bin <= r_in_wptr_bin + 1 when s_in_write = '1'
                 else r_in_wptr_bin;

  in_wptr: process(p_in_clk, s_in_resetn, s_in_write)
  begin
    if s_in_resetn = '0' then
      r_in_wptr_bin <= (others => '0');
    elsif rising_edge(p_in_clk) then
      r_in_wptr_bin <= s_in_wptr_bin;
    end if;
  end process in_wptr;

  out_rptr: process(p_out_clk, s_out_resetn, s_out_read)
  begin
    if s_out_resetn = '0' then
      r_out_rptr_bin <= (others => '0');
    elsif rising_edge(p_out_clk) then
      r_out_rptr_bin <= s_out_rptr_bin;
    end if;
  end process out_rptr;

  in_wptr_gray: nsl.util.gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_in_wptr_gray,
      p_binary => std_ulogic_vector(r_in_wptr_bin)
      );

  out_rptr_gray: nsl.util.gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_out_rptr_gray,
      p_binary => std_ulogic_vector(r_out_rptr_bin)
      );

  ram: hwdep.ram.ram_2p
    generic map(
      addr_size => count_width,
      data_size => data_width
      )
    port map(
      p_clk1 => p_in_clk,
      p_addr1 => std_ulogic_vector(r_in_wptr_bin),
      p_wren1 => s_in_write,
      p_wdata1 => p_in_data,
      p_rdata1 => open,

      p_clk2 => p_out_clk,
      p_addr2 => std_ulogic_vector(s_out_rptr_bin),
      p_wren2 => '0',
      p_wdata2 => (others => 'X'),
      p_rdata2 => p_out_data
      );

  s_out_read <= p_out_read and not r_out_empty;
  s_in_write <= p_in_write and not r_in_full;

  process(s_out_rptr_gray, s_in_wptr_gray)
  begin
    s_going_full <= (s_in_wptr_gray(s_in_wptr_gray'high - 1)
                     xnor s_out_rptr_gray(s_out_rptr_gray'high))
                    and
                    (s_in_wptr_gray(s_in_wptr_gray'high)
                     xor s_out_rptr_gray(s_out_rptr_gray'high - 1));
    s_going_empty <= (s_in_wptr_gray(s_in_wptr_gray'high - 1)
                     xor s_out_rptr_gray(s_out_rptr_gray'high))
                    and
                    (s_in_wptr_gray(s_in_wptr_gray'high)
                     xnor s_out_rptr_gray(s_out_rptr_gray'high - 1));
  end process;

  process(s_going_full, s_going_empty, s_common_rst)
  begin
    if s_going_empty = '1' or s_common_rst = '0' then
      r_state <= GOING_EMPTY;
    elsif s_going_full = '1' then
      r_state <= GOING_FULL;
    end if;
  end process;

  s_ptr_equal <= s_in_wptr_gray = s_out_rptr_gray;
  
  process(p_in_clk, r_state, s_ptr_equal)
  begin
    if r_state = GOING_FULL and s_ptr_equal then
      r_in_full <= '1';
    elsif rising_edge(p_in_clk) then
      r_in_full <= '0';
    end if;
  end process;

  process(p_out_clk, r_state, s_ptr_equal)
  begin
    if r_state = GOING_EMPTY and s_ptr_equal then
      r_out_empty <= '1';
    elsif rising_edge(p_out_clk) then
      r_out_empty <= '0';
    end if;
  end process;

  p_in_full_n <= not r_in_full;
  p_out_empty_n <= not r_out_empty;
  
end ram;
