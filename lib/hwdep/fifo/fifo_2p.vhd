library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.numeric.log2;
use util.sync.sync_rising_edge;
use util.gray.all;

library hwdep;
use hwdep.ram.all;

entity fifo_2p is
  generic(
    data_width : integer;
    depth      : integer;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);

    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_write  : in  std_ulogic;
    p_in_full_n : out std_ulogic;

    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_read    : in  std_ulogic;
    p_out_empty_n : out std_ulogic
    );
end fifo_2p;

architecture inferred of fifo_2p is

  type state is (
    GOING_EMPTY,
    GOING_FULL
    );
  
  constant count_width : integer := log2(depth);
  subtype count_t is std_ulogic_vector(count_width-1 downto 0);
  subtype count_u is unsigned(count_width-1 downto 0);

  signal s_out_resetn, s_in_resetn : std_ulogic;

  signal r_in_wptr_bin, r_out_rptr_bin: count_u;
  signal s_in_wptr_bin, s_out_rptr_bin: count_u;
  signal r_state: state;

  signal s_in_wptr_gray, s_out_rptr_gray: count_t;

  signal s_going_full, s_going_empty: std_ulogic;
  signal s_ptr_equal: boolean;
  
  signal r_in_full_n, r_out_empty_n : std_ulogic;
  signal s_in_full_n, s_out_empty_n : std_ulogic;
  signal s_in_write, s_out_read : std_ulogic;
  signal r_out_data_valid : std_ulogic;

  constant is_synchronous: boolean := clk_count = 1;
  constant cin: natural := 0;
  constant cout: natural := clk_count-1;
  
begin
  
  reset_async: if not is_synchronous generate
    sync: util.sync.sync_multi_resetn
      generic map(
        clk_count => 2
        )
      port map(
        p_clk => p_clk,
        p_resetn => p_resetn,
        p_resetn_sync(0) => s_in_resetn,
        p_resetn_sync(1) => s_out_resetn
        );
  end generate;

  reset_sync: if is_synchronous generate
    s_out_resetn <= p_resetn;
    s_in_resetn <= p_resetn;
  end generate;
  
  s_out_rptr_bin <= r_out_rptr_bin + 1 when s_out_read = '1' else r_out_rptr_bin;
  s_in_wptr_bin <= r_in_wptr_bin + 1 when s_in_write = '1' else r_in_wptr_bin;

  in_wptr: process(p_clk(cin), s_in_resetn)
  begin
    if s_in_resetn = '0' then
      r_in_wptr_bin <= (others => '0');
    elsif rising_edge(p_clk(cin)) then
      r_in_wptr_bin <= s_in_wptr_bin;
    end if;
  end process in_wptr;

  out_rptr: process(p_clk(cout), s_out_resetn)
  begin
    if s_out_resetn = '0' then
      r_out_rptr_bin <= (others => '0');
    elsif rising_edge(p_clk(cout)) then
      r_out_rptr_bin <= s_out_rptr_bin;
    end if;
  end process out_rptr;

  in_wptr_gray: util.gray.gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_in_wptr_gray,
      p_binary => std_ulogic_vector(r_in_wptr_bin)
      );

  out_rptr_gray: util.gray.gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_out_rptr_gray,
      p_binary => std_ulogic_vector(r_out_rptr_bin)
      );

  ram: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => count_width,
      data_size => data_width,
      clk_count => clk_count,
      bypass => is_synchronous
      )
    port map(
      p_clk => p_clk,
      
      p_waddr => std_ulogic_vector(r_in_wptr_bin),
      p_wen => s_in_write,
      p_wdata => p_in_data,

      p_raddr => std_ulogic_vector(r_out_rptr_bin),
      p_ren => s_out_read,
      p_rdata => p_out_data
      );

  s_out_read <= (not r_out_data_valid or p_out_read) and r_out_empty_n;
  s_in_write <= p_in_write and r_in_full_n;

  going_async: if not is_synchronous generate
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

    process(s_going_full, s_going_empty, s_in_resetn)
    begin
      if s_going_empty = '1' or s_in_resetn = '0' then
        r_state <= GOING_EMPTY;
      elsif s_going_full = '1' then
        r_state <= GOING_FULL;
      end if;
    end process;

    s_ptr_equal <= s_in_wptr_gray = s_out_rptr_gray;
  end generate;

  going_sync: if is_synchronous generate
    process(s_in_resetn, p_clk(cin))
    begin
      if s_in_resetn = '0' then
        r_state <= GOING_EMPTY;

      elsif rising_edge(p_clk(cin)) then
        if p_in_write = '0' and (r_out_data_valid = '0' or p_out_read = '1') then
          r_state <= GOING_EMPTY;
        elsif p_in_write = '1' and (r_out_data_valid = '1' and p_out_read = '0') then
          r_state <= GOING_FULL;
        end if;
      end if;
    end process;

    s_ptr_equal <= r_in_wptr_bin = r_out_rptr_bin;
  end generate;

  process(s_out_resetn, p_clk(cout))
  begin
    if s_out_resetn = '0' then
      r_out_data_valid <= '0';

    elsif rising_edge(p_clk(cout)) then
      if p_out_read = '1' or r_out_data_valid = '0' then
        r_out_data_valid <= s_out_read;
      end if;
    end if;
  end process;

  s_in_full_n <= '0' when r_state = GOING_FULL and s_ptr_equal else '1';
  s_out_empty_n <= '0' when r_state = GOING_EMPTY and s_ptr_equal else '1';

  in_full_sync: util.sync.sync_rising_edge
    port map(
      p_in => s_in_full_n,
      p_clk => p_clk(cin),
      p_out => r_in_full_n
      );

  out_empty_sync: util.sync.sync_rising_edge
    port map(
      p_in => s_out_empty_n,
      p_clk => p_clk(cout),
      p_out => r_out_empty_n
      );

  p_in_full_n <= r_in_full_n;
  p_out_empty_n <= r_out_data_valid;
  
end inferred;
