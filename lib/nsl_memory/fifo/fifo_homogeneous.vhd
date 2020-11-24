library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_math, nsl_memory;

entity fifo_homogeneous is
  generic(
    data_width_c   : integer;
    word_count_c        : integer;
    clock_count_c    : natural range 1 to 2;
    input_slice_c : boolean := false;
    output_slice_c : boolean := false;
    register_counters_c : boolean := false
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i    : in  std_ulogic_vector(0 to clock_count_c-1);

    out_data_o          : out std_ulogic_vector(data_width_c-1 downto 0);
    out_ready_i         : in  std_ulogic;
    out_valid_o         : out std_ulogic;
    out_available_min_o : out integer range 0 to word_count_c;
    out_available_o     : out integer range 0 to word_count_c + 1;

    in_data_i       : in  std_ulogic_vector(data_width_c-1 downto 0);
    in_valid_i      : in  std_ulogic;
    in_ready_o      : out std_ulogic;
    in_free_o       : out integer range 0 to word_count_c
    );

end fifo_homogeneous;

architecture ram2 of fifo_homogeneous is

  constant ptr_width : natural := nsl_math.arith.log2(word_count_c-1);
  subtype mem_ptr_t is unsigned(ptr_width-1 downto 0);
  subtype peer_pos_t is std_ulogic_vector(ptr_width downto 0);
  subtype data_t is std_ulogic_vector(data_width_c-1 downto 0);
  constant c_idx_high : mem_ptr_t := to_unsigned(word_count_c-1, ptr_width);
  constant c_is_pow2 : boolean := c_idx_high = (c_idx_high'range => '1');
  constant is_synchronous: boolean := clock_count_c = 1;
  constant is_bisynchronous: boolean := clock_count_c = 2;

  signal s_resetn: std_ulogic_vector(0 to clock_count_c-1);

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

  signal int_in_data_i       : std_ulogic_vector(data_width_c-1 downto 0);
  signal int_in_valid_i      : std_ulogic;
  signal int_in_ready_o      : std_ulogic;

  signal int_out_data_o       : std_ulogic_vector(data_width_c-1 downto 0);
  signal int_out_valid_o      : std_ulogic;
  signal int_out_ready_i      : std_ulogic;

begin

  with_input_slice: if input_slice_c
  generate
    input_slice: nsl_memory.fifo.fifo_register_slice
      generic map(
        data_width_c => data_width_c
        )
      port map(
        clock_i => clock_i(0),
        reset_n_i => s_resetn(0),

        out_data_o => int_in_data_i,
        out_ready_i => int_in_ready_o,
        out_valid_o => int_in_valid_i,

        in_data_i => in_data_i,
        in_valid_i => in_valid_i,
        in_ready_o => in_ready_o
        );
  end generate;

  without_input_slice: if not input_slice_c
  generate
    int_in_data_i <= in_data_i;
    int_in_valid_i <= in_valid_i;
    in_ready_o <= int_in_ready_o;
  end generate;

  with_output_slice: if output_slice_c
  generate
    output_slice: nsl_memory.fifo.fifo_register_slice
      generic map(
        data_width_c => data_width_c
        )
      port map(
        clock_i => clock_i(clock_count_c-1),
        reset_n_i => s_resetn(clock_count_c-1),

        out_data_o => out_data_o,
        out_ready_i => out_ready_i,
        out_valid_o => out_valid_o,

        in_data_i => int_out_data_o,
        in_valid_i => int_out_valid_o,
        in_ready_o => int_out_ready_i
        );
  end generate;

  without_output_slice: if not output_slice_c
  generate
    out_data_o <= int_out_data_o;
    out_valid_o <= int_out_valid_o;
    int_out_ready_i <= out_ready_i;
  end generate;
  
  assert is_synchronous or c_is_pow2
    report "Bisynchronous fifos can only work for power-of-two depths"
    severity failure;

  async: if not is_synchronous generate
  begin
    reset_sync: nsl_clocking.async.async_multi_reset
      generic map(
        domain_count_c => 2
        )
      port map(
        clock_i => clock_i,
        master_i => reset_n_i,
        slave_o => s_resetn
        );

    out_wptr: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => peer_pos_t'length,
        input_is_gray_c => true,
        output_is_gray_c => true
        )
      port map(
        clock_in_i => clock_i(0),
        clock_out_i => clock_i(clock_count_c-1),
        data_i => unsigned(s_left.local_pos),
        peer_pos_t(data_o) => s_right.peer_pos
        );

    in_rptr: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => peer_pos_t'length,
        decode_stage_count_c => (peer_pos_t'length + 3) / 4,
        input_is_gray_c => true,
        output_is_gray_c => true
        )
      port map(
        clock_in_i => clock_i(clock_count_c-1),
        clock_out_i => clock_i(0),
        data_i => unsigned(s_right.local_pos),
        peer_pos_t(data_o) => s_left.peer_pos
        );
  end generate;

  sync: if is_synchronous generate
    s_resetn(0) <= reset_n_i;

    -- only insert a 2-cycle delay (ram latency)

    out_wptr: nsl_clocking.intradomain.intradomain_multi_reg
      generic map(
        data_width_c => peer_pos_t'length
        )
      port map(
        clock_i => clock_i(0),
        data_i => std_ulogic_vector(s_left.local_pos),
        peer_pos_t(data_o) => s_right.peer_pos
        );

    in_rptr: nsl_clocking.intradomain.intradomain_multi_reg
      generic map(
        data_width_c => peer_pos_t'length
        )
      port map(
        clock_i => clock_i(0),
        data_i => std_ulogic_vector(s_right.local_pos),
        peer_pos_t(data_o) => s_left.peer_pos
        );
  end generate;

  ctr_in: nsl_memory.fifo.fifo_pointer
    generic map(
      ptr_width_c => mem_ptr_t'length,
      wrap_count_c => word_count_c,
      equal_can_move_c => true,
      gray_position_c => is_bisynchronous,
      peer_ahead_c => true
      )
    port map(
      reset_n_i => s_resetn(0),
      clock_i => clock_i(0),
      inc_i => s_left.inc_req,
      ack_o => s_left.inc_ack,
      peer_position_i => s_left.peer_pos,
      local_position_o => s_left.local_pos,
      mem_ptr_o => s_left.mem_ptr,
      used_count_o => s_left.used,
      free_count_o => s_left.free
      );

  ctr_out: nsl_memory.fifo.fifo_pointer
    generic map(
      ptr_width_c => mem_ptr_t'length,
      wrap_count_c => word_count_c,
      equal_can_move_c => false,
      gray_position_c => is_bisynchronous,
      peer_ahead_c => false
      )
    port map(
      reset_n_i => s_resetn(clock_count_c-1),
      clock_i => clock_i(clock_count_c-1),
      inc_i => s_right.inc_req,
      ack_o => s_right.inc_ack,
      peer_position_i => s_right.peer_pos,
      local_position_o => s_right.local_pos,
      mem_ptr_o => s_right.mem_ptr,
      used_count_o => s_right.used,
      free_count_o => s_right.free
      );

  registered_counters: if register_counters_c
  generate
    in_counter: process(clock_i(0))
    begin
      if rising_edge(clock_i(0)) then
        in_free_o <= to_integer(to_01(s_left.free));
      end if;
    end process;

    out_counter: process(clock_i(clock_count_c-1))
    begin
      if rising_edge(clock_i(clock_count_c-1)) then
        out_available_min_o <= to_integer(to_01(s_right.used));
        out_available_o <= to_integer(to_01(s_right.used) + unsigned(std_ulogic_vector'("") & (r.valid or r.direct)));
      end if;
    end process;
  end generate;

  non_registered_counters: if not register_counters_c
  generate
    in_free_o <= to_integer(to_01(s_left.free));
    out_available_min_o <= to_integer(to_01(s_right.used));
    out_available_o <= to_integer(to_01(s_right.used) + unsigned(std_ulogic_vector'("") & (r.valid or r.direct)));
  end generate;
  
  ram: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => data_t'length,
      clock_count_c => clock_count_c
      )
    port map(
      clock_i => clock_i,

      write_address_i => s_left.mem_ptr,
      write_en_i => s_left.mem_en,
      write_data_i => int_in_data_i,

      read_address_i => s_right.mem_ptr,
      read_en_i => s_right.mem_en,
      read_data_o => s_read_data
      );

  int_in_ready_o <= s_left.inc_ack;
  s_left.mem_en <= s_left.inc_ack and int_in_valid_i;
  s_left.inc_req <= int_in_valid_i;

  regs: process (clock_i, s_resetn)
  begin
    if clock_i(clock_count_c-1)'event and clock_i(clock_count_c-1) = '1' then
      if s_resetn(clock_count_c-1) = '0' then
        r.valid <= '0';
        r.direct <= '0';
        r.data <= (others => '-');
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process(int_out_ready_i, r, s_right.mem_ptr, s_read_data, s_right.inc_ack)
  begin
    rin <= r;

    rin.direct <= s_right.inc_ack;

    if r.valid = '0' and int_out_ready_i = '0' then
      rin.valid <= r.direct;
      rin.data <= s_read_data;
      rin.addr <= s_right.mem_ptr;
    elsif r.valid = '1' and int_out_ready_i = '1' then
      rin.valid <= '0';
      rin.data <= (others => '-');
      rin.addr <= (others => '-');
    end if;
  end process;

  s_right.inc_req <= int_out_ready_i or (not r.valid and not r.direct);
  s_right.mem_en <= s_right.inc_ack and (int_out_ready_i or not r.valid);
  int_out_valid_o <= r.valid or r.direct;
  int_out_data_o <= r.data when r.valid = '1' else s_read_data;

end ram2;
