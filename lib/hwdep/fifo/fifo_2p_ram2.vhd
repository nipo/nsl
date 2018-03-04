library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.numeric.all;
use util.sync.all;

library hwdep;
use hwdep.ram.all;

entity fifo_2p is
  generic(
    data_width : integer;
    depth      : integer;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn : in  std_ulogic;
    p_clk    : in  std_ulogic_vector(0 to clk_count-1);

    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_read    : in  std_ulogic;
    p_out_empty_n : out std_ulogic;

    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_write  : in  std_ulogic;
    p_in_full_n : out std_ulogic
    );
end fifo_2p;

architecture ram2 of fifo_2p is

  subtype count_t is std_ulogic_vector(log2(depth)-1 downto 0);
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);

  signal s_resetn: std_ulogic_vector(0 to clk_count-1);
  signal s_out_wptr, s_in_rptr: unsigned(count_t'range);

  signal s_read2 : std_ulogic;

  constant is_synchronous: boolean := clk_count = 1;

  type regs_t is record
    blocked: std_ulogic;
    move: std_ulogic;
    ptr: unsigned(count_t'range);
  end record;

  signal out_r, out_rin, in_r, in_rin: regs_t;

begin

  -- MEMO: Dont use rising_edge with record/arrays (ISE bug)
  regs_in: process (p_clk(0), s_resetn(0))
  begin
    if s_resetn(0) = '0' then
      in_r.ptr <= (others => '0');
      in_r.blocked <= '0';
      in_r.move <= '0';
    elsif p_clk(0)'event and p_clk(0) = '1' then
      in_r <= in_rin;
    end if;
  end process;

  regs_out: process(p_clk(clk_count-1), s_resetn(clk_count-1))
  begin
    if s_resetn(clk_count-1) = '0' then
      out_r.ptr <= (others => '0');
      out_r.blocked <= '1';
      out_r.move <= '0';
    elsif p_clk(clk_count-1)'event and p_clk(clk_count-1) = '1' then
      out_r <= out_rin;
    end if;
  end process;

  transition_in: process(in_r, p_in_write, s_in_rptr)
  begin
    in_rin <= in_r;

    in_rin.move <= '0';

    if in_r.blocked = '0' then
      if p_in_write = '1' then
        in_rin.ptr <= in_r.ptr + 1;
        in_rin.move <= '1';

        if s_in_rptr = in_r.ptr + 1 then
          in_rin.blocked <= '1';
        end if;
      end if;
    elsif s_in_rptr /= in_r.ptr then
      in_rin.blocked <= '0';
    end if;
  end process;

  transition_out: process(out_r, p_out_read, s_out_wptr)
  begin
    out_rin <= out_r;

    out_rin.move <= '0';

    if out_r.blocked = '0' then
      if p_out_read = '1' then
        out_rin.ptr <= out_r.ptr + 1;
        out_rin.move <= '1';

        if s_out_wptr = out_r.ptr + 1 then
          out_rin.blocked <= '1';
        end if;
      end if;
    elsif s_out_wptr /= out_r.ptr then
      out_rin.blocked <= '0';
    end if;
  end process;


  async: if not is_synchronous generate
    reset_sync: util.sync.sync_multi_resetn
      generic map(
        clk_count => 2
        )
      port map(
        p_clk => p_clk,
        p_resetn => p_resetn,
        p_resetn_sync => s_resetn
        );

    out_wptr: sync_cross_counter
      generic map(
        data_width => count_t'length
        )
      port map(
        p_in_clk => p_clk(0),
        p_out_clk => p_clk(clk_count-1),
        p_in => in_r.ptr,
        p_out => s_out_wptr
        );

    in_rptr: sync_cross_counter
      generic map(
        data_width => count_t'length
        )
      port map(
        p_in_clk => p_clk(clk_count-1),
        p_out_clk => p_clk(0),
        p_in => out_r.ptr,
        p_out => s_in_rptr
        );
  end generate;

  sync: if is_synchronous generate
    s_resetn(0) <= p_resetn;

--    out_wptr: sync_reg
--      generic map(
--        data_width => count_t'length,
--        cycle_count => 1
--        )
--      port map(
--        p_clk => p_clk(0),
--        p_in => std_ulogic_vector(in_r.ptr),
--        unsigned(p_out) => s_out_wptr
--        );
--
--    in_rptr: sync_reg
--      generic map(
--        data_width => count_t'length,
--        cycle_count => 1
--        )
--      port map(
--        p_clk => p_clk(0),
--        p_in => std_ulogic_vector(out_r.ptr),
--        unsigned(p_out) => s_in_rptr
--        );
    s_in_rptr <= out_r.ptr;
    s_out_wptr <= in_r.ptr;
  end generate;

  s_read2 <= out_rin.move or out_r.blocked;

  ram: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => count_t'length,
      data_size => word_t'length,
      clk_count => clk_count,
      bypass => is_synchronous
      )
    port map(
      p_clk => p_clk,

      p_waddr => std_ulogic_vector(in_r.ptr),
      p_wen => in_rin.move,
      p_wdata => p_in_data,

      p_raddr => std_ulogic_vector(out_rin.ptr),
      p_ren => s_read2,
      p_rdata => p_out_data
      );

  p_in_full_n <= not in_r.blocked and s_resetn(0);
  p_out_empty_n <= not out_r.blocked;

end ram2;
