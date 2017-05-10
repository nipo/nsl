library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.util.all;
use nsl.fifo.all;

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

architecture rtl of fifo_async is

  constant count_width : integer := log2(depth);
  subtype count_t is std_ulogic_vector(count_width-1 downto 0);
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type fifo_t is array(depth - 1 downto 0) of word_t;

  signal r_mem: fifo_t;

  signal s_out_rst, s_in_rst : std_ulogic_vector(1 downto 0);
  signal s_out_resetn, s_in_resetn : std_ulogic;

  signal s_in_wptr : count_t;
  signal s_out_wptr_gray, s_in_wptr_gray : count_t;
  signal s_out_rptr : count_t;
  signal s_out_rptr_gray, s_in_rptr_gray : count_t;
  signal r_out_wptr, r_in_wptr : count_t;
  signal r_out_rptr, r_in_rptr : count_t;

  signal s_in_full : std_ulogic;
  signal s_out_empty : std_ulogic;

begin

  reset_sync_out: reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_clk => p_out_clk,
      p_resetn_sync => s_out_rst(1)
      );

  reset_sync_in: reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_clk => p_in_clk,
      p_resetn_sync => s_in_rst(1)
      );

  reset_sync_out_in: reset_synchronizer
    port map(
      p_resetn => s_out_rst(1),
      p_clk => p_in_clk,
      p_resetn_sync => s_in_rst(0)
      );

  reset_sync_in_out: reset_synchronizer
    port map(
      p_resetn => s_in_rst(1),
      p_clk => p_out_clk,
      p_resetn_sync => s_out_rst(0)
      );

  s_out_resetn <= s_out_rst(1) and s_out_rst(0);
  s_in_resetn <= s_in_rst(1) and s_in_rst(0);

  out_rptr_gray: gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_binary => r_out_rptr,
      p_gray => s_out_rptr_gray
      );
  
  in_rptr_gray: resync_reg
    generic map(
      cycle_count => 2,
      data_width => count_width
      )
    port map(
      p_clk => p_in_clk,
      p_in => s_out_rptr_gray,
      p_out => s_in_rptr_gray
      );

  in_rptr: gray_decoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_in_rptr_gray,
      p_binary => r_in_rptr
      );

  in_wptr_gray: gray_encoder
    generic map(
      data_width => count_width
      )
    port map(
      p_binary => r_in_wptr,
      p_gray => s_in_wptr_gray
      );
  
  out_wptr_gray: resync_reg
    generic map(
      cycle_count => 2,
      data_width => count_width
      )
    port map(
      p_clk => p_out_clk,
      p_in => s_in_wptr_gray,
      p_out => s_out_wptr_gray
      );

  out_wptr: gray_decoder
    generic map(
      data_width => count_width
      )
    port map(
      p_gray => s_out_wptr_gray,
      p_binary => r_out_wptr
      );
  
  in_reg: process(p_in_clk, s_in_resetn)
  begin
    if s_in_resetn = '0' then
      r_in_wptr <= (others => '0');
    elsif rising_edge(p_in_clk) then
      r_in_wptr <= s_in_wptr;
    end if;
  end process in_reg;

  in_mem: process(p_in_clk, s_in_full)
  begin
    if rising_edge(p_in_clk) and s_in_full = '0' then
      r_mem(to_integer(unsigned(r_in_wptr))) <= p_in_data;
    end if;
  end process;

  out_reg: process(p_out_clk, s_out_resetn)
  begin
    if s_out_resetn = '0' then
      r_out_rptr <= (others => '0');
    elsif rising_edge(p_out_clk) then
      r_out_rptr <= s_out_rptr;
    end if;
  end process out_reg;

  s_out_empty <= '1' when r_out_rptr = r_out_wptr else '0';
  s_in_full <= '1' when std_ulogic_vector(unsigned(r_in_wptr) + 1) = r_in_rptr else '0';

  out_moore: process(r_mem, r_out_rptr, s_out_resetn, s_out_empty)
  begin
    p_out_data <= r_mem(to_integer(unsigned(r_out_rptr)));
    p_out_empty_n <= not s_out_empty and s_out_resetn;
  end process;

  in_moore: process(s_in_full, s_in_resetn)
  begin
    p_in_full_n <= not s_in_full and s_in_resetn;
  end process;

  rptr: process(p_out_read, r_out_rptr, s_out_empty)
  begin
    s_out_rptr <= r_out_rptr;

    if s_out_empty = '0' and p_out_read = '1' then
      if unsigned(r_out_rptr) = to_unsigned(depth - 1, r_out_rptr'length) then
        s_out_rptr <= (others => '0');
      else
        s_out_rptr <= std_ulogic_vector(unsigned(r_out_rptr) + 1);
      end if;
    end if;
  end process;

  wptr: process(p_in_write, r_in_wptr, s_in_full)
  begin
    s_in_wptr <= r_in_wptr;

    if s_in_full = '0' and p_in_write = '1' then
      if unsigned(r_in_wptr) = to_unsigned(depth - 1, r_out_rptr'length) then
        s_in_wptr <= (others => '0');
      else
        s_in_wptr <= std_ulogic_vector(unsigned(r_in_wptr) + 1);
      end if;
    end if;
  end process;

  
end rtl;
