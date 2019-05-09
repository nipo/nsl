library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, hwdep;

entity fifo_2p is
  generic(
    data_width : integer;
    depth      : integer;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn : in  std_ulogic;
    p_clk    : in  std_ulogic_vector(0 to clk_count-1);

    p_out_data      : out std_ulogic_vector(data_width-1 downto 0);
    p_out_ready     : in  std_ulogic;
    p_out_valid     : out std_ulogic;

    p_in_data       : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_valid      : in  std_ulogic;
    p_in_ready      : out std_ulogic
    );

end fifo_2p;

architecture ram2 of fifo_2p is

  constant ptr_width : natural := util.numeric.log2(depth);
  subtype mem_ptr_t is unsigned(ptr_width-1 downto 0);
  subtype peer_ptr_t is std_ulogic_vector(ptr_width downto 0);
  subtype data_t is std_ulogic_vector(data_width-1 downto 0);
  constant c_idx_high : mem_ptr_t := to_unsigned(depth-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  constant is_synchronous: boolean := clk_count = 1;
  constant is_bisynchronous: boolean := clk_count = 2;

  signal s_resetn: std_ulogic_vector(0 to clk_count-1);
  signal s_out_wptr, s_in_rptr, s_out_rptr, s_in_wptr: peer_ptr_t;
  signal s_mem_wptr, s_mem_rptr: mem_ptr_t;
  signal s_mem_write, s_mem_ren, s_rptr_valid: std_ulogic;
  signal s_write_ack, s_rptr_inc: std_ulogic;
  signal s_read_data: data_t;
  
  type regs_t is record
    direct, valid: std_logic;
    addr: mem_ptr_t;
    data: data_t;
  end record;

  signal r, rin: regs_t;

begin

  assert is_synchronous or c_is_pow2
    report "Bisynchronous fifos can only work for power-of-two depths"
    severity failure;
  
  async: if not is_synchronous generate
  begin
    reset_sync: util.sync.sync_multi_resetn
      generic map(
        clk_count => 2
        )
      port map(
        p_clk => p_clk,
        p_resetn => p_resetn,
        p_resetn_sync => s_resetn
        );

    out_wptr: util.sync.sync_cross_counter
      generic map(
        data_width => peer_ptr_t'length,
        input_is_gray => true,
        output_is_gray => true
        )
      port map(
        p_in_clk => p_clk(0),
        p_out_clk => p_clk(clk_count-1),
        p_in => unsigned(s_in_wptr),
        peer_ptr_t(p_out) => s_out_wptr
        );

    in_rptr: util.sync.sync_cross_counter
      generic map(
        data_width => peer_ptr_t'length,
        decode_stage_count => (peer_ptr_t'length + 3) / 4,
        input_is_gray => true,
        output_is_gray => true
        )
      port map(
        p_in_clk => p_clk(clk_count-1),
        p_out_clk => p_clk(0),
        p_in => unsigned(s_out_rptr),
        peer_ptr_t(p_out) => s_in_rptr
        );
  end generate;

  sync: if is_synchronous generate
    s_resetn(0) <= p_resetn;

    -- only insert a 2-cycle delay (ram latency)

    out_wptr: util.sync.sync_reg
      generic map(
        data_width => peer_ptr_t'length,
        cross_region => false
        )
      port map(
        p_clk => p_clk(0),
        p_in => std_ulogic_vector(s_in_wptr),
        peer_ptr_t(p_out) => s_out_wptr
        );

    in_rptr: util.sync.sync_reg
      generic map(
        data_width => peer_ptr_t'length,
        cross_region => false
        )
      port map(
        p_clk => p_clk(0),
        p_in => std_ulogic_vector(s_out_rptr),
        peer_ptr_t(p_out) => s_in_rptr
        );
  end generate;
  
  ctr_in: hwdep.fifo.fifo_pointer
    generic map(
      ptr_width => mem_ptr_t'length,
      wrap_count => depth,
      equal_can_move => true,
      ptr_are_gray => is_bisynchronous
      )
    port map(
      p_resetn => s_resetn(0),
      p_clk => p_clk(0),
      p_inc => p_in_valid,
      p_ack => s_write_ack,
      p_peer_ptr => s_in_rptr,
      p_local_ptr => s_in_wptr,
      p_mem_ptr => s_mem_wptr
      );

  ctr_out: hwdep.fifo.fifo_pointer
    generic map(
      ptr_width => mem_ptr_t'length,
      wrap_count => depth,
      equal_can_move => false,
      ptr_are_gray => is_bisynchronous,
      increment_early => true
      )
    port map(
      p_resetn => s_resetn(clk_count-1),
      p_clk => p_clk(clk_count-1),
      p_inc => s_rptr_inc,
      p_ack => s_rptr_valid,
      p_peer_ptr => s_out_wptr,
      p_local_ptr => s_out_rptr,
      p_mem_ptr => s_mem_rptr
      );

  ram: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => mem_ptr_t'length,
      data_size => data_t'length,
      clk_count => clk_count,
      bypass => is_synchronous
      )
    port map(
      p_clk => p_clk,

      p_waddr => std_ulogic_vector(s_mem_wptr),
      p_wen => s_mem_write,
      p_wdata => p_in_data,

      p_raddr => std_ulogic_vector(s_mem_rptr),
      p_ren => s_mem_ren,
      p_rdata => s_read_data
      );

  p_in_ready <= s_write_ack;
  s_mem_write <= s_write_ack and p_in_valid;
  
  regs: process (p_clk, s_resetn)
  begin
    if p_clk(clk_count-1)'event and p_clk(clk_count-1) = '1' then
      if s_resetn(clk_count-1) = '0' then
        r.valid <= '0';
        r.direct <= '0';
        r.data <= (others => '-');
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process(p_out_ready, r, s_mem_rptr, s_read_data, s_rptr_valid)
  begin
    rin <= r;

    rin.direct <= s_rptr_valid;

    if r.valid = '0' and p_out_ready = '0' then
      rin.valid <= r.direct;
      rin.data <= s_read_data;
      rin.addr <= s_mem_rptr;
    elsif r.valid = '1' and p_out_ready = '1' then
      rin.valid <= '0';
      rin.data <= (others => '-');
      rin.addr <= (others => '-');
    end if;
  end process;

  s_rptr_inc <= p_out_ready or (not r.valid and not r.direct);
  s_mem_ren <= s_rptr_valid and (p_out_ready or not r.valid);
  p_out_valid <= r.valid or r.direct;
  p_out_data <= r.data when r.valid = '1' else s_read_data;
  
end ram2;
