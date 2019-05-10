library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, hwdep;

entity fifo_2p is
  generic(
    data_width   : integer;
    depth        : integer;
    clk_count    : natural range 1 to 2
    );
  port(
    p_resetn : in  std_ulogic;
    p_clk    : in  std_ulogic_vector(0 to clk_count-1);

    p_out_data      : out std_ulogic_vector(data_width-1 downto 0);
    p_out_ready     : in  std_ulogic;
    p_out_valid     : out std_ulogic;
    p_out_used      : out integer range 0 to depth;
    p_out_free      : out integer range 0 to depth;

    p_in_data       : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_valid      : in  std_ulogic;
    p_in_ready      : out std_ulogic;
    p_in_used       : out integer range 0 to depth;
    p_in_free       : out integer range 0 to depth
    );

end fifo_2p;

architecture ram2 of fifo_2p is

  constant ptr_width : natural := util.numeric.log2(depth);
  subtype mem_ptr_t is unsigned(ptr_width-1 downto 0);
  subtype peer_pos_t is std_ulogic_vector(ptr_width downto 0);
  subtype data_t is std_ulogic_vector(data_width-1 downto 0);
  constant c_idx_high : mem_ptr_t := to_unsigned(depth-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  constant is_synchronous: boolean := clk_count = 1;
  constant is_bisynchronous: boolean := clk_count = 2;

  signal s_resetn: std_ulogic_vector(0 to clk_count-1);

  type side_info_t is
  record
    -- Position (gray if async), resynchronized and compared for full/empty.
    local_pos, peer_pos : peer_pos_t;
    -- pointers
    used, free : unsigned(ptr_width downto 0);
    -- Memory pointer
    mem_ptr : mem_ptr_t;
    -- Memory and pointer logic control signals
    mem_en : std_ulogic;
    inc_req : std_ulogic;
    inc_ack : std_ulogic;
  end record;

  signal s_left, s_right: side_info_t;

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
        data_width => peer_pos_t'length,
        input_is_gray => true,
        output_is_gray => true
        )
      port map(
        p_in_clk => p_clk(0),
        p_out_clk => p_clk(clk_count-1),
        p_in => unsigned(s_left.local_pos),
        peer_pos_t(p_out) => s_right.peer_pos
        );

    in_rptr: util.sync.sync_cross_counter
      generic map(
        data_width => peer_pos_t'length,
        decode_stage_count => (peer_pos_t'length + 3) / 4,
        input_is_gray => true,
        output_is_gray => true
        )
      port map(
        p_in_clk => p_clk(clk_count-1),
        p_out_clk => p_clk(0),
        p_in => unsigned(s_right.local_pos),
        peer_pos_t(p_out) => s_left.peer_pos
        );
  end generate;

  sync: if is_synchronous generate
    s_resetn(0) <= p_resetn;

    -- only insert a 2-cycle delay (ram latency)

    out_wptr: util.sync.sync_reg
      generic map(
        data_width => peer_pos_t'length,
        cross_region => false
        )
      port map(
        p_clk => p_clk(0),
        p_in => std_ulogic_vector(s_left.local_pos),
        peer_pos_t(p_out) => s_right.peer_pos
        );

    in_rptr: util.sync.sync_reg
      generic map(
        data_width => peer_pos_t'length,
        cross_region => false
        )
      port map(
        p_clk => p_clk(0),
        p_in => std_ulogic_vector(s_right.local_pos),
        peer_pos_t(p_out) => s_left.peer_pos
        );
  end generate;

  ctr_in: hwdep.fifo.fifo_pointer
    generic map(
      ptr_width => mem_ptr_t'length,
      wrap_count => depth,
      equal_can_move => true,
      gray_position => is_bisynchronous,
      increment_early => false,
      peer_ahead => true
      )
    port map(
      p_resetn => s_resetn(0),
      p_clk => p_clk(0),
      p_inc => s_left.inc_req,
      p_ack => s_left.inc_ack,
      p_peer_position => s_left.peer_pos,
      p_local_position => s_left.local_pos,
      p_mem_ptr => s_left.mem_ptr,
      p_used_count => s_left.used,
      p_free_count => s_left.free
      );

  ctr_out: hwdep.fifo.fifo_pointer
    generic map(
      ptr_width => mem_ptr_t'length,
      wrap_count => depth,
      equal_can_move => false,
      gray_position => is_bisynchronous,
      increment_early => true,
      peer_ahead => false
      )
    port map(
      p_resetn => s_resetn(clk_count-1),
      p_clk => p_clk(clk_count-1),
      p_inc => s_right.inc_req,
      p_ack => s_right.inc_ack,
      p_peer_position => s_right.peer_pos,
      p_local_position => s_right.local_pos,
      p_mem_ptr => s_right.mem_ptr,
      p_used_count => s_right.used,
      p_free_count => s_right.free
      );

  p_in_used <= to_integer(to_01(s_left.used));
  p_in_free <= to_integer(to_01(s_left.free));
  p_out_used <= to_integer(to_01(s_right.used));
  p_out_free <= to_integer(to_01(s_right.free));

  ram: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => mem_ptr_t'length,
      data_size => data_t'length,
      clk_count => clk_count,
      bypass => is_synchronous
      )
    port map(
      p_clk => p_clk,

      p_waddr => std_ulogic_vector(s_left.mem_ptr),
      p_wen => s_left.mem_en,
      p_wdata => p_in_data,

      p_raddr => std_ulogic_vector(s_right.mem_ptr),
      p_ren => s_right.mem_en,
      p_rdata => s_read_data
      );

  p_in_ready <= s_left.inc_ack;
  s_left.mem_en <= s_left.inc_ack and p_in_valid;
  s_left.inc_req <= p_in_valid;

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

  transition: process(p_out_ready, r, s_right.mem_ptr, s_read_data, s_right.inc_ack)
  begin
    rin <= r;

    rin.direct <= s_right.inc_ack;

    if r.valid = '0' and p_out_ready = '0' then
      rin.valid <= r.direct;
      rin.data <= s_read_data;
      rin.addr <= s_right.mem_ptr;
    elsif r.valid = '1' and p_out_ready = '1' then
      rin.valid <= '0';
      rin.data <= (others => '-');
      rin.addr <= (others => '-');
    end if;
  end process;

  s_right.inc_req <= p_out_ready or (not r.valid and not r.direct);
  s_right.mem_en <= s_right.inc_ack and (p_out_ready or not r.valid);
  p_out_valid <= r.valid or r.direct;
  p_out_data <= r.data when r.valid = '1' else s_read_data;

end ram2;
