library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math, nsl_logic, nsl_memory;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_routing.all;
use nsl_amba.crossbar_priv.all;
use nsl_math.arith.all;
use nsl_logic.bool.all;

-- Slave port: handles one external slave's connection to the crossbar.
-- Performs arbitration among masters and ID widening/stripping.
-- Write data is forwarded in the order write addresses were accepted.
entity axi4_mm_crossbar_slave_port is
  generic(
    master_config_c : config_t;
    slave_config_c : config_t;
    master_count_c : positive;
    aw_tracking_depth_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Internal crossbar interface (from each master port)
    -- AR channel
    int_ar_i : in address_vector(0 to master_count_c-1);
    int_ar_ready_o : out std_ulogic;
    int_ar_request_i : in std_ulogic_vector(0 to master_count_c-1);
    int_ar_grant_o : out std_ulogic_vector(0 to master_count_c-1);

    -- AW channel
    int_aw_i : in address_vector(0 to master_count_c-1);
    int_aw_ready_o : out std_ulogic;
    int_aw_request_i : in std_ulogic_vector(0 to master_count_c-1);
    int_aw_grant_o : out std_ulogic_vector(0 to master_count_c-1);

    -- W channel
    int_w_i : in write_data_vector(0 to master_count_c-1);
    int_w_ready_o : out std_ulogic_vector(0 to master_count_c-1);
    int_w_select_i : in std_ulogic_vector(0 to master_count_c-1);

    -- R channel (broadcast to all masters, they filter by ID)
    int_r_o : out read_data_t;
    int_r_valid_o : out std_ulogic_vector(0 to master_count_c-1);
    int_r_ready_i : in std_ulogic_vector(0 to master_count_c-1);

    -- B channel (broadcast to all masters, they filter by ID)
    int_b_o : out write_response_t;
    int_b_valid_o : out std_ulogic_vector(0 to master_count_c-1);
    int_b_ready_i : in std_ulogic_vector(0 to master_count_c-1);

    -- External slave interface (slave_config_c)
    ext_o : out master_t;
    ext_i : in slave_t
    );
end entity;

architecture beh of axi4_mm_crossbar_slave_port is

  constant route_width_c : natural := slave_config_c.id_width - master_config_c.id_width;
  constant master_idx_width_c : positive := max(1, log2(master_count_c));

  type ar_state_t is (
    ST_AR_RESET,
    ST_AR_IDLE,
    ST_AR_FORWARD
    );

  type aw_state_t is (
    ST_AW_RESET,
    ST_AW_IDLE,
    ST_AW_FORWARD
    );

  type w_state_t is (
    ST_W_RESET,
    ST_W_IDLE,
    ST_W_FORWARD
    );

  type regs_t is record
    ar_state : ar_state_t;
    ar_selected : natural range 0 to master_count_c-1;
    ar_last_selected : natural range 0 to master_count_c-1;

    aw_state : aw_state_t;
    aw_selected : natural range 0 to master_count_c-1;
    aw_last_selected : natural range 0 to master_count_c-1;

    w_state : w_state_t;
    w_selected : natural range 0 to master_count_c-1;
  end record;

  signal r, rin : regs_t;

  signal order_in_data, order_out_data : std_ulogic_vector(master_idx_width_c-1 downto 0);
  signal order_in_valid, order_in_ready : std_ulogic;
  signal order_out_valid, order_out_ready : std_ulogic;

  function widen_id(master_id : std_ulogic_vector;
                    master_index : natural) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(slave_config_c.id_width-1 downto 0);
  begin
    ret := (others => '0');
    ret(master_config_c.id_width-1 downto 0) := master_id(master_config_c.id_width-1 downto 0);
    if route_width_c > 0 then
      ret(slave_config_c.id_width-1 downto master_config_c.id_width) :=
        std_ulogic_vector(to_unsigned(master_index, route_width_c));
    end if;
    return ret;
  end function;

  function extract_master_index(slave_id : std_ulogic_vector) return natural
  is
  begin
    if route_width_c > 0 then
      return to_integer(unsigned(slave_id(slave_config_c.id_width-1 downto master_config_c.id_width)));
    else
      return 0;
    end if;
  end function;

  function round_robin_select(requests : std_ulogic_vector;
                              last_selected : natural;
                              count : positive) return natural
  is
    variable idx : natural;
  begin
    for i in 0 to count-1
    loop
      idx := (last_selected + 1 + i) mod count;
      if requests(idx) = '1' then
        return idx;
      end if;
    end loop;
    return last_selected;
  end function;

begin

  assert route_width_c >= 0 and (route_width_c = 0 or master_count_c <= 2**route_width_c)
    report "slave_config_c.id_width must be >= master_config_c.id_width + ceil_log2(master_count_c)"
    severity failure;

  -- Masters of accepted write addresses, in order
  write_order_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => master_idx_width_c,
      word_count_c => aw_tracking_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      in_data_i => order_in_data,
      in_valid_i => order_in_valid,
      in_ready_o => order_in_ready,
      out_data_o => order_out_data,
      out_valid_o => order_out_valid,
      out_ready_i => order_out_ready
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

  transition: process(r, int_ar_i, int_ar_request_i, int_aw_i, int_aw_request_i,
                      int_w_i, int_w_select_i, int_r_ready_i, int_b_ready_i, ext_i,
                      order_in_ready, order_out_valid, order_out_data)
    variable ar_any_request : boolean;
    variable aw_any_request : boolean;
  begin
    rin <= r;

    ar_any_request := int_ar_request_i /= (int_ar_request_i'range => '0');
    aw_any_request := int_aw_request_i /= (int_aw_request_i'range => '0');

    -- AR channel state machine
    case r.ar_state is
      when ST_AR_RESET =>
        rin.ar_state <= ST_AR_IDLE;
        rin.ar_selected <= 0;
        rin.ar_last_selected <= 0;

      when ST_AR_IDLE =>
        if ar_any_request then
          rin.ar_selected <= round_robin_select(int_ar_request_i, r.ar_last_selected, master_count_c);
          rin.ar_state <= ST_AR_FORWARD;
        end if;

      when ST_AR_FORWARD =>
        if is_ready(slave_config_c, ext_i.ar) and int_ar_request_i(r.ar_selected) = '1' then
          rin.ar_last_selected <= r.ar_selected;
          rin.ar_state <= ST_AR_IDLE;
        end if;
    end case;

    -- AW channel state machine
    case r.aw_state is
      when ST_AW_RESET =>
        rin.aw_state <= ST_AW_IDLE;
        rin.aw_selected <= 0;
        rin.aw_last_selected <= 0;

      when ST_AW_IDLE =>
        if aw_any_request and order_in_ready = '1' then
          rin.aw_selected <= round_robin_select(int_aw_request_i, r.aw_last_selected, master_count_c);
          rin.aw_state <= ST_AW_FORWARD;
        end if;

      when ST_AW_FORWARD =>
        if is_ready(slave_config_c, ext_i.aw) and int_aw_request_i(r.aw_selected) = '1' then
          rin.aw_last_selected <= r.aw_selected;
          rin.aw_state <= ST_AW_IDLE;
        end if;
    end case;

    -- W channel state machine
    case r.w_state is
      when ST_W_RESET =>
        rin.w_state <= ST_W_IDLE;
        rin.w_selected <= 0;

      when ST_W_IDLE =>
        if order_out_valid = '1' then
          rin.w_selected <= to_integer(unsigned(order_out_data));
          rin.w_state <= ST_W_FORWARD;
        end if;

      when ST_W_FORWARD =>
        if is_ready(slave_config_c, ext_i.w)
          and is_valid(master_config_c, int_w_i(r.w_selected))
          and int_w_select_i(r.w_selected) = '1' then
          if is_last(master_config_c, int_w_i(r.w_selected)) then
            -- Chain the next burst without an idle cycle.
            if order_out_valid = '1' then
              rin.w_selected <= to_integer(unsigned(order_out_data));
            else
              rin.w_state <= ST_W_IDLE;
            end if;
          end if;
        end if;
    end case;
  end process;

  outputs: process(r, int_ar_i, int_ar_request_i, int_aw_i, int_aw_request_i,
                   int_w_i, int_w_select_i, int_r_ready_i, int_b_ready_i, ext_i,
                   order_in_ready, order_out_valid)
    variable r_master_idx : natural range 0 to master_count_c-1;
    variable b_master_idx : natural range 0 to master_count_c-1;
    variable ar_v : address_t;
    variable aw_v : address_t;
    variable w_v : write_data_t;
    variable int_r_v : read_data_t;
    variable int_b_v : write_response_t;
    variable aw_any_request : boolean;
  begin
    aw_any_request := int_aw_request_i /= (int_aw_request_i'range => '0');

    -- Default outputs
    ext_o.ar <= address_defaults(slave_config_c);
    ext_o.aw <= address_defaults(slave_config_c);
    ext_o.w <= write_data_defaults(slave_config_c);
    ext_o.r <= handshake_defaults(slave_config_c);
    ext_o.b <= handshake_defaults(slave_config_c);

    int_ar_ready_o <= '0';
    int_ar_grant_o <= (others => '0');
    int_aw_ready_o <= '0';
    int_aw_grant_o <= (others => '0');
    int_w_ready_o <= (others => '0');
    order_in_data <= (others => '0');
    order_in_valid <= '0';
    order_out_ready <= '0';

    int_r_o <= read_data_defaults(master_config_c);
    int_r_valid_o <= (others => '0');
    int_b_o <= write_response_defaults(master_config_c);
    int_b_valid_o <= (others => '0');

    -- AR channel
    case r.ar_state is
      when ST_AR_RESET | ST_AR_IDLE =>
        null;

      when ST_AR_FORWARD =>
        int_ar_grant_o(r.ar_selected) <= '1';
        int_ar_ready_o <= ext_i.ar.ready;

        ar_v := int_ar_i(r.ar_selected);
        ar_v.id := (others => '0');
        ar_v.id(slave_config_c.id_width-1 downto 0) :=
          widen_id(int_ar_i(r.ar_selected).id, r.ar_selected);
        ar_v.valid := int_ar_request_i(r.ar_selected);
        ext_o.ar <= ar_v;
    end case;

    -- AW channel
    case r.aw_state is
      when ST_AW_RESET =>
        null;

      when ST_AW_IDLE =>
        -- Write data order is set by address arbitration, write data
        -- may flow before the address is accepted
        if aw_any_request and order_in_ready = '1' then
          order_in_data <= std_ulogic_vector(to_unsigned(
            round_robin_select(int_aw_request_i, r.aw_last_selected, master_count_c),
            master_idx_width_c));
          order_in_valid <= '1';
        end if;

      when ST_AW_FORWARD =>
        int_aw_grant_o(r.aw_selected) <= '1';
        int_aw_ready_o <= ext_i.aw.ready;

        aw_v := int_aw_i(r.aw_selected);
        aw_v.id := (others => '0');
        aw_v.id(slave_config_c.id_width-1 downto 0) :=
          widen_id(int_aw_i(r.aw_selected).id, r.aw_selected);
        aw_v.valid := int_aw_request_i(r.aw_selected);
        ext_o.aw <= aw_v;
    end case;

    -- W channel
    case r.w_state is
      when ST_W_RESET =>
        null;

      when ST_W_IDLE =>
        order_out_ready <= order_out_valid;

      when ST_W_FORWARD =>
        int_w_ready_o(r.w_selected) <= ext_i.w.ready and int_w_select_i(r.w_selected);
        w_v := int_w_i(r.w_selected);
        w_v.valid := int_w_i(r.w_selected).valid and int_w_select_i(r.w_selected);
        ext_o.w <= w_v;
        if is_ready(slave_config_c, ext_i.w) and w_v.valid = '1'
          and is_last(master_config_c, int_w_i(r.w_selected)) then
          order_out_ready <= order_out_valid;
        end if;
    end case;

    -- R channel: route based on ID MSBs
    if is_valid(slave_config_c, ext_i.r) then
      r_master_idx := extract_master_index(ext_i.r.id);
      int_r_valid_o(r_master_idx) <= '1';
      ext_o.r <= accept(slave_config_c, int_r_ready_i(r_master_idx) = '1');
    end if;

    int_r_v := read_data_defaults(master_config_c);
    int_r_v.id := (others => '0');
    int_r_v.id(master_config_c.id_width-1 downto 0) := ext_i.r.id(master_config_c.id_width-1 downto 0);
    int_r_v.data := ext_i.r.data;
    int_r_v.resp := ext_i.r.resp;
    int_r_v.last := ext_i.r.last;
    int_r_v.user := ext_i.r.user;
    int_r_v.valid := '0';
    int_r_o <= int_r_v;

    -- B channel: route based on ID MSBs
    if is_valid(slave_config_c, ext_i.b) then
      b_master_idx := extract_master_index(ext_i.b.id);
      int_b_valid_o(b_master_idx) <= '1';
      ext_o.b <= accept(slave_config_c, int_b_ready_i(b_master_idx) = '1');
    end if;

    int_b_v := write_response_defaults(master_config_c);
    int_b_v.id := (others => '0');
    int_b_v.id(master_config_c.id_width-1 downto 0) := ext_i.b.id(master_config_c.id_width-1 downto 0);
    int_b_v.resp := ext_i.b.resp;
    int_b_v.user := ext_i.b.user;
    int_b_v.valid := '0';
    int_b_o <= int_b_v;
  end process;

end architecture;
