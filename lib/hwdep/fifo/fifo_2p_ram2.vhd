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
    p_out_available : out natural range 0 to depth;

    p_in_data       : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_valid      : in  std_ulogic;
    p_in_ready      : out std_ulogic;
    p_in_free       : out natural range 0 to depth
    );
end fifo_2p;

architecture ram2 of fifo_2p is

  subtype ptr_t is unsigned(util.numeric.log2(depth)-1 downto 0);
  subtype data_t is std_ulogic_vector(data_width-1 downto 0);

  signal s_resetn: std_ulogic_vector(0 to clk_count-1);
  signal s_out_wptr, s_in_rptr, s_out_rptr, s_in_wptr: ptr_t;
  signal s_mem_write, s_mem_read: std_ulogic;

  constant is_synchronous: boolean := clk_count = 1;

begin

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
        data_width => ptr_t'length
        )
      port map(
        p_in_clk => p_clk(0),
        p_out_clk => p_clk(clk_count-1),
        p_in => s_in_wptr,
        p_out => s_out_wptr
        );

    in_rptr: util.sync.sync_cross_counter
      generic map(
        data_width => ptr_t'length,
        decode_stage_count => (ptr_t'length + 3) / 4
        )
      port map(
        p_in_clk => p_clk(clk_count-1),
        p_out_clk => p_clk(0),
        p_in => s_out_rptr,
        p_out => s_in_rptr
        );
  end generate;

  sync: if is_synchronous generate
    s_resetn(0) <= p_resetn;
    s_in_rptr <= s_out_rptr;
    s_out_wptr <= s_in_wptr;
  end generate;
  
  ctr_in: hwdep.fifo.fifo_write_pointer
    generic map(
      ptr_width => ptr_t'length,
      wrap_count => depth
      )
    port map(
      p_resetn => s_resetn(0),
      p_clk => p_clk(0),
      p_valid => p_in_valid,
      p_ready => p_in_ready,
      p_peer_ptr => s_in_rptr,
      p_mem_ptr => s_in_wptr,
      p_write => s_mem_write
      );

  ctr_out: hwdep.fifo.fifo_read_pointer
    generic map(
      ptr_width => ptr_t'length,
      wrap_count => depth
      )
    port map(
      p_resetn => s_resetn(clk_count-1),
      p_clk => p_clk(clk_count-1),
      p_valid => p_out_valid,
      p_ready => p_out_ready,
      p_peer_ptr => s_out_wptr,
      p_mem_ptr => s_out_rptr,
      p_read => s_mem_read
      );

  ram: hwdep.ram.ram_2p_r_w
    generic map(
      addr_size => ptr_t'length,
      data_size => data_t'length,
      clk_count => clk_count,
      bypass => is_synchronous
      )
    port map(
      p_clk => p_clk,

      p_waddr => std_ulogic_vector(s_in_wptr),
      p_wen => s_mem_write,
      p_wdata => p_in_data,

      p_raddr => std_ulogic_vector(s_out_rptr),
      p_ren => s_mem_read,
      p_rdata => p_out_data
      );

end ram2;
