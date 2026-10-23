library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math, nsl_logic, nsl_memory;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_routing.all;
use nsl_amba.crossbar_priv.all;
use nsl_math.arith.all;
use nsl_logic.bool.all;

-- Master port: handles one external master's connection to the crossbar.
-- Performs address decode, request generation, and W channel correlation.
-- Reads, and writes, may only be outstanding to one slave at a time,
-- this keeps responses in order and W channel free of deadlocks.
entity axi4_mm_crossbar_master_port is
  generic(
    master_config_c : config_t;
    slave_config_c : config_t;
    slave_count_c : positive;
    routing_table_c : nsl_amba.address.address_vector;
    default_slave_c : natural;
    master_index_c : natural;
    aw_tracking_depth_c : positive := 4;
    max_outstanding_c : positive := 16
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- External master interface (master_config_c)
    ext_i : in master_t;
    ext_o : out slave_t;

    -- Internal crossbar interface (slave_config_c, one set per slave)
    -- AR channel
    int_ar_o : out nsl_amba.axi4_mm.address_t;
    int_ar_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
    int_ar_request_o : out std_ulogic_vector(0 to slave_count_c-1);
    int_ar_grant_i : in std_ulogic_vector(0 to slave_count_c-1);

    -- AW channel
    int_aw_o : out nsl_amba.axi4_mm.address_t;
    int_aw_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
    int_aw_request_o : out std_ulogic_vector(0 to slave_count_c-1);
    int_aw_grant_i : in std_ulogic_vector(0 to slave_count_c-1);

    -- W channel (follows AW routing)
    int_w_o : out write_data_t;
    int_w_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
    int_w_select_o : out std_ulogic_vector(0 to slave_count_c-1);

    -- R channel (routed by ID from slave ports)
    int_r_i : in read_data_t;
    int_r_valid_i : in std_ulogic;
    int_r_ready_o : out std_ulogic;

    -- B channel (routed by ID from slave ports)
    int_b_i : in write_response_t;
    int_b_valid_i : in std_ulogic;
    int_b_ready_o : out std_ulogic
    );
end entity;

architecture beh of axi4_mm_crossbar_master_port is

  constant route_width_c : natural := slave_config_c.id_width - master_config_c.id_width;
  constant slave_idx_width_c : natural := log2(slave_count_c);
  constant fifo_width_c : natural := slave_idx_width_c + master_config_c.len_width;

  type ar_state_t is (
    ST_AR_RESET,
    ST_AR_IDLE,
    ST_AR_REQUEST
    );

  type aw_state_t is (
    ST_AW_RESET,
    ST_AW_IDLE,
    ST_AW_REQUEST
    );

  type w_state_t is (
    ST_W_RESET,
    ST_W_IDLE,
    ST_W_BURST
    );

  type regs_t is record
    ar_state : ar_state_t;
    ar_target : natural range 0 to slave_count_c-1;
    ar_pending : natural range 0 to max_outstanding_c;

    aw_state : aw_state_t;
    aw_target : natural range 0 to slave_count_c-1;
    aw_pending : natural range 0 to max_outstanding_c;

    w_state : w_state_t;
    w_target : natural range 0 to slave_count_c-1;
    w_beats_left : unsigned(master_config_c.len_width-1 downto 0);
  end record;

  signal r, rin : regs_t;

  -- AW/W tracking FIFO signals
  signal fifo_in_data : std_ulogic_vector(fifo_width_c-1 downto 0);
  signal fifo_in_valid : std_ulogic;
  signal fifo_in_ready : std_ulogic;
  signal fifo_out_data : std_ulogic_vector(fifo_width_c-1 downto 0);
  signal fifo_out_valid : std_ulogic;
  signal fifo_out_ready : std_ulogic;

  function decode_address(addr : unsigned) return natural
  is
  begin
    return nsl_amba.address.routing_table_lookup(master_config_c.address_width,
                                                 routing_table_c,
                                                 addr,
                                                 default_slave_c);
  end function;

  function may_issue(pending : natural;
                     current_target, target : natural) return boolean
  is
  begin
    return pending = 0
      or (target = current_target and pending < max_outstanding_c);
  end function;

  function pack_fifo_data(target : natural; len_m1 : unsigned) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(fifo_width_c-1 downto 0);
  begin
    ret := (others => '0');
    if slave_idx_width_c > 0 then
      ret(slave_idx_width_c-1 downto 0) := std_ulogic_vector(to_unsigned(target, slave_idx_width_c));
    end if;
    if master_config_c.len_width > 0 then
      ret(slave_idx_width_c + master_config_c.len_width - 1 downto slave_idx_width_c) :=
        std_ulogic_vector(resize(len_m1, master_config_c.len_width));
    end if;
    return ret;
  end function;

  function unpack_fifo_target(data : std_ulogic_vector) return natural
  is
  begin
    if slave_idx_width_c > 0 then
      return to_integer(unsigned(data(slave_idx_width_c-1 downto 0)));
    else
      return 0;
    end if;
  end function;

  function unpack_fifo_len_m1(data : std_ulogic_vector) return unsigned
  is
  begin
    if master_config_c.len_width > 0 then
      return unsigned(data(slave_idx_width_c + master_config_c.len_width - 1 downto slave_idx_width_c));
    else
      return to_unsigned(0, 1);
    end if;
  end function;

begin

  -- AW/W tracking FIFO
  tracking_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => fifo_width_c,
      word_count_c => aw_tracking_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      in_data_i => fifo_in_data,
      in_valid_i => fifo_in_valid,
      in_ready_o => fifo_in_ready,
      out_data_o => fifo_out_data,
      out_valid_o => fifo_out_valid,
      out_ready_i => fifo_out_ready
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.ar_state <= ST_AR_RESET;
      r.aw_state <= ST_AW_RESET;
      r.w_state <= ST_W_RESET;
    end if;
  end process;

  transition: process(r, ext_i, int_ar_ready_i, int_ar_grant_i,
                      int_aw_ready_i, int_aw_grant_i,
                      int_w_ready_i, fifo_in_ready, fifo_out_valid, fifo_out_data,
                      int_r_i, int_r_valid_i, int_b_valid_i)
    variable ar_target_v : natural range 0 to slave_count_c-1;
    variable aw_target_v : natural range 0 to slave_count_c-1;
    variable w_target_v : natural range 0 to slave_count_c-1;
    variable w_len_m1_v : unsigned(master_config_c.len_width-1 downto 0);
    variable ar_issue, ar_retire, aw_issue, aw_retire : boolean;
  begin
    rin <= r;

    ar_issue := false;
    aw_issue := false;
    ar_retire := r.ar_pending /= 0 and int_r_valid_i = '1' and ext_i.r.ready = '1'
                 and is_last(master_config_c, int_r_i);
    aw_retire := r.aw_pending /= 0 and int_b_valid_i = '1' and ext_i.b.ready = '1';

    -- AR channel state machine
    case r.ar_state is
      when ST_AR_RESET =>
        rin.ar_state <= ST_AR_IDLE;
        rin.ar_target <= 0;

      when ST_AR_IDLE =>
        if is_valid(master_config_c, ext_i.ar) then
          ar_target_v := decode_address(address(master_config_c, ext_i.ar));
          if may_issue(r.ar_pending, r.ar_target, ar_target_v) then
            ar_issue := true;
            rin.ar_target <= ar_target_v;
            rin.ar_state <= ST_AR_REQUEST;
          end if;
        end if;

      when ST_AR_REQUEST =>
        if int_ar_grant_i(r.ar_target) = '1' and int_ar_ready_i(r.ar_target) = '1' then
          rin.ar_state <= ST_AR_IDLE;
        end if;
    end case;

    -- AW channel state machine
    case r.aw_state is
      when ST_AW_RESET =>
        rin.aw_state <= ST_AW_IDLE;
        rin.aw_target <= 0;

      when ST_AW_IDLE =>
        if is_valid(master_config_c, ext_i.aw) and fifo_in_ready = '1' then
          aw_target_v := decode_address(address(master_config_c, ext_i.aw));
          if may_issue(r.aw_pending, r.aw_target, aw_target_v) then
            aw_issue := true;
            rin.aw_target <= aw_target_v;
            rin.aw_state <= ST_AW_REQUEST;
          end if;
        end if;

      when ST_AW_REQUEST =>
        if int_aw_grant_i(r.aw_target) = '1' and int_aw_ready_i(r.aw_target) = '1' then
          rin.aw_state <= ST_AW_IDLE;
        end if;
    end case;

    if ar_issue and not ar_retire then
      rin.ar_pending <= r.ar_pending + 1;
    elsif ar_retire and not ar_issue then
      rin.ar_pending <= r.ar_pending - 1;
    end if;

    if aw_issue and not aw_retire then
      rin.aw_pending <= r.aw_pending + 1;
    elsif aw_retire and not aw_issue then
      rin.aw_pending <= r.aw_pending - 1;
    end if;

    if r.ar_state = ST_AR_RESET then
      rin.ar_pending <= 0;
    end if;

    if r.aw_state = ST_AW_RESET then
      rin.aw_pending <= 0;
    end if;

    -- W channel state machine
    case r.w_state is
      when ST_W_RESET =>
        rin.w_state <= ST_W_IDLE;
        rin.w_target <= 0;
        rin.w_beats_left <= (others => '0');

      when ST_W_IDLE =>
        if fifo_out_valid = '1' then
          w_target_v := unpack_fifo_target(fifo_out_data);
          w_len_m1_v := unpack_fifo_len_m1(fifo_out_data);
          rin.w_target <= w_target_v;
          rin.w_beats_left <= w_len_m1_v;
          rin.w_state <= ST_W_BURST;
        end if;

      when ST_W_BURST =>
        if is_valid(master_config_c, ext_i.w) and int_w_ready_i(r.w_target) = '1' then
          if is_last(master_config_c, ext_i.w) then
            -- Chain the next burst without an idle cycle.
            if fifo_out_valid = '1' then
              rin.w_target <= unpack_fifo_target(fifo_out_data);
              rin.w_beats_left <= unpack_fifo_len_m1(fifo_out_data);
            else
              rin.w_state <= ST_W_IDLE;
            end if;
          else
            if master_config_c.len_width > 0 then
              rin.w_beats_left <= r.w_beats_left - 1;
            end if;
          end if;
        end if;
    end case;
  end process;

  outputs: process(r, ext_i, int_ar_ready_i, int_ar_grant_i,
                   int_aw_ready_i, int_aw_grant_i, int_w_ready_i,
                   int_r_i, int_r_valid_i, int_b_i, int_b_valid_i,
                   fifo_in_ready, fifo_out_valid, fifo_out_data)
    variable aw_target_v : natural range 0 to slave_count_c-1;
  begin
    -- Default outputs
    ext_o.ar <= handshake_defaults(master_config_c);
    ext_o.aw <= handshake_defaults(master_config_c);
    ext_o.w <= handshake_defaults(master_config_c);
    ext_o.r <= read_data_defaults(master_config_c);
    ext_o.b <= write_response_defaults(master_config_c);

    int_ar_o <= address_defaults(slave_config_c);
    int_ar_request_o <= (others => '0');

    int_aw_o <= address_defaults(slave_config_c);
    int_aw_request_o <= (others => '0');

    int_w_o <= write_data_defaults(slave_config_c);
    int_w_select_o <= (others => '0');

    int_r_ready_o <= '0';
    int_b_ready_o <= '0';

    fifo_in_data <= (others => '0');
    fifo_in_valid <= '0';
    fifo_out_ready <= '0';

    -- AR channel
    case r.ar_state is
      when ST_AR_RESET | ST_AR_IDLE =>
        null;

      when ST_AR_REQUEST =>
        int_ar_request_o(r.ar_target) <= '1';
        int_ar_o <= ext_i.ar;
        int_ar_o.valid <= int_ar_grant_i(r.ar_target);
        ext_o.ar <= accept(master_config_c,
                           int_ar_grant_i(r.ar_target) = '1' and int_ar_ready_i(r.ar_target) = '1');
    end case;

    -- AW channel
    case r.aw_state is
      when ST_AW_RESET =>
        null;

      when ST_AW_IDLE =>
        -- Write data may flow as soon as the target is known
        if is_valid(master_config_c, ext_i.aw) and fifo_in_ready = '1' then
          aw_target_v := decode_address(address(master_config_c, ext_i.aw));
          if may_issue(r.aw_pending, r.aw_target, aw_target_v) then
            fifo_in_data <= pack_fifo_data(aw_target_v, length_m1(master_config_c, ext_i.aw, master_config_c.len_width));
            fifo_in_valid <= '1';
          end if;
        end if;

      when ST_AW_REQUEST =>
        int_aw_request_o(r.aw_target) <= '1';
        int_aw_o <= ext_i.aw;
        int_aw_o.valid <= int_aw_grant_i(r.aw_target);

        ext_o.aw <= accept(master_config_c,
                           int_aw_grant_i(r.aw_target) = '1' and int_aw_ready_i(r.aw_target) = '1');
    end case;

    -- W channel
    case r.w_state is
      when ST_W_RESET | ST_W_IDLE =>
        -- Pop from FIFO when entering burst state
        if fifo_out_valid = '1' then
          fifo_out_ready <= '1';
        end if;

      when ST_W_BURST =>
        int_w_select_o(r.w_target) <= '1';
        int_w_o <= ext_i.w;
        ext_o.w <= accept(master_config_c, int_w_ready_i(r.w_target) = '1');
        if is_valid(master_config_c, ext_i.w) and int_w_ready_i(r.w_target) = '1'
          and is_last(master_config_c, ext_i.w) then
          fifo_out_ready <= fifo_out_valid;
        end if;
    end case;

    -- R channel: forward to external master
    if int_r_valid_i = '1' then
      ext_o.r <= int_r_i;
      ext_o.r.valid <= '1';
      int_r_ready_o <= ext_i.r.ready;
    end if;

    -- B channel: forward to external master
    if int_b_valid_i = '1' then
      ext_o.b <= int_b_i;
      ext_o.b.valid <= '1';
      int_b_ready_o <= ext_i.b.ready;
    end if;
  end process;

end architecture;
