library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_routing.all;
use nsl_amba.crossbar_priv.all;
use nsl_math.arith.all;
use nsl_logic.bool.all;

entity axi4_mm_crossbar is
  generic(
    master_config_c : config_t;
    slave_config_c : config_t;
    master_count_c : positive;
    routing_table_c : nsl_amba.address.address_vector;
    default_slave_c : integer := -1;
    aw_tracking_depth_c : positive := 4;
    max_outstanding_c : positive := 16;
    master_slice_c : boolean := false;
    slave_slice_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    slave_i : in master_vector(0 to master_count_c-1);
    slave_o : out slave_vector(0 to master_count_c-1);

    master_o : out master_vector(0 to routing_table_c'length-1);
    master_i : in slave_vector(0 to routing_table_c'length-1)
    );
end entity;

architecture beh of axi4_mm_crossbar is

  constant external_slave_count_c : natural := routing_table_c'length;
  constant has_internal_error_slave_c : boolean := default_slave_c < 0;
  constant internal_slave_count_c : natural := external_slave_count_c + if_else(has_internal_error_slave_c, 1, 0);
  constant error_slave_index_c : natural := external_slave_count_c;
  constant actual_default_slave_c : natural := if_else(has_internal_error_slave_c, error_slave_index_c, default_slave_c);

  constant route_width_c : natural := slave_config_c.id_width - master_config_c.id_width;

  -- Internal signals between master and slave ports
  -- AR channel: per-master to all-slaves
  type ar_address_array_t is array (0 to master_count_c-1) of nsl_amba.axi4_mm.address_t;
  type ar_request_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);
  type ar_grant_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);
  type ar_ready_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);

  signal master_ar_address : ar_address_array_t;
  signal master_ar_request : ar_request_array_t;
  signal master_ar_grant : ar_grant_array_t;
  signal master_ar_ready : ar_ready_array_t;

  -- AW channel: per-master to all-slaves
  type aw_address_array_t is array (0 to master_count_c-1) of nsl_amba.axi4_mm.address_t;
  type aw_request_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);
  type aw_grant_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);
  type aw_ready_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);

  signal master_aw_address : aw_address_array_t;
  signal master_aw_request : aw_request_array_t;
  signal master_aw_grant : aw_grant_array_t;
  signal master_aw_ready : aw_ready_array_t;

  -- W channel: per-master to all-slaves
  type w_data_array_t is array (0 to master_count_c-1) of write_data_t;
  type w_select_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);
  type w_ready_array_t is array (0 to master_count_c-1) of std_ulogic_vector(0 to internal_slave_count_c-1);

  signal master_w_data : w_data_array_t;
  signal master_w_select : w_select_array_t;
  signal master_w_ready : w_ready_array_t;

  -- R channel: per-slave broadcast to all masters
  type r_data_array_t is array (0 to internal_slave_count_c-1) of read_data_t;
  type r_valid_array_t is array (0 to internal_slave_count_c-1) of std_ulogic_vector(0 to master_count_c-1);
  type r_ready_array_t is array (0 to internal_slave_count_c-1) of std_ulogic_vector(0 to master_count_c-1);

  signal slave_r_data : r_data_array_t;
  signal slave_r_valid : r_valid_array_t;
  signal slave_r_ready : r_ready_array_t;

  -- B channel: per-slave broadcast to all masters
  type b_data_array_t is array (0 to internal_slave_count_c-1) of write_response_t;
  type b_valid_array_t is array (0 to internal_slave_count_c-1) of std_ulogic_vector(0 to master_count_c-1);
  type b_ready_array_t is array (0 to internal_slave_count_c-1) of std_ulogic_vector(0 to master_count_c-1);

  signal slave_b_data : b_data_array_t;
  signal slave_b_valid : b_valid_array_t;
  signal slave_b_ready : b_ready_array_t;

  -- Slave port interface signals (aggregated for slave ports)
  signal slave_ar_ready : std_ulogic_vector(0 to internal_slave_count_c-1);
  signal slave_aw_ready : std_ulogic_vector(0 to internal_slave_count_c-1);

  -- Internal error slave signals
  signal error_slave_axi_o : master_t;
  signal error_slave_axi_i : slave_t;

  -- Merged R/B signals for each master
  type merged_r_data_t is array (0 to master_count_c-1) of read_data_t;
  type merged_b_data_t is array (0 to master_count_c-1) of write_response_t;
  signal merged_r_data : merged_r_data_t;
  signal merged_r_valid : std_ulogic_vector(0 to master_count_c-1);
  signal merged_b_data : merged_b_data_t;
  signal merged_b_valid : std_ulogic_vector(0 to master_count_c-1);
  signal master_r_ready : std_ulogic_vector(0 to master_count_c-1);
  signal master_b_ready : std_ulogic_vector(0 to master_count_c-1);

begin

  -- Configuration assertions
  assert route_width_c >= 0 and (master_count_c = 1 or route_width_c >= log2(master_count_c))
    report "slave_config_c.id_width must be >= master_config_c.id_width + ceil_log2(master_count_c)"
    severity failure;

  assert slave_config_c.address_width = master_config_c.address_width
    report "master_config_c and slave_config_c must have same address_width"
    severity failure;

  assert slave_config_c.data_bus_width_l2 = master_config_c.data_bus_width_l2
    report "master_config_c and slave_config_c must have same data_bus_width_l2"
    severity failure;

  assert slave_config_c.len_width = master_config_c.len_width
    report "master_config_c and slave_config_c must have same len_width"
    severity failure;

  -- Master ports generation
  master_ports: for m in 0 to master_count_c-1 generate
    direct: if not master_slice_c generate
      master_port_inst: work.crossbar_priv.axi4_mm_crossbar_master_port
        generic map(
          master_config_c => master_config_c,
          slave_config_c => slave_config_c,
          slave_count_c => internal_slave_count_c,
          routing_table_c => routing_table_c,
          default_slave_c => actual_default_slave_c,
          master_index_c => m,
          aw_tracking_depth_c => aw_tracking_depth_c,
          max_outstanding_c => max_outstanding_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          ext_i => slave_i(m),
          ext_o => slave_o(m),
          int_ar_o => master_ar_address(m),
          int_ar_ready_i => master_ar_ready(m),
          int_ar_request_o => master_ar_request(m),
          int_ar_grant_i => master_ar_grant(m),
          int_aw_o => master_aw_address(m),
          int_aw_ready_i => master_aw_ready(m),
          int_aw_request_o => master_aw_request(m),
          int_aw_grant_i => master_aw_grant(m),
          int_w_o => master_w_data(m),
          int_w_ready_i => master_w_ready(m),
          int_w_select_o => master_w_select(m),
          int_r_i => merged_r_data(m),
          int_r_valid_i => merged_r_valid(m),
          int_r_ready_o => master_r_ready(m),
          int_b_i => merged_b_data(m),
          int_b_valid_i => merged_b_valid(m),
          int_b_ready_o => master_b_ready(m)
          );
    end generate;

    sliced: if master_slice_c generate
      signal sliced_m : master_t;
      signal sliced_s : slave_t;
    begin
      slice: nsl_amba.mm_fifo.axi4_mm_slice
        generic map(
          config_c => master_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          slave_i => slave_i(m),
          slave_o => slave_o(m),
          master_o => sliced_m,
          master_i => sliced_s
          );

      master_port_inst: work.crossbar_priv.axi4_mm_crossbar_master_port
        generic map(
          master_config_c => master_config_c,
          slave_config_c => slave_config_c,
          slave_count_c => internal_slave_count_c,
          routing_table_c => routing_table_c,
          default_slave_c => actual_default_slave_c,
          master_index_c => m,
          aw_tracking_depth_c => aw_tracking_depth_c,
          max_outstanding_c => max_outstanding_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          ext_i => sliced_m,
          ext_o => sliced_s,
          int_ar_o => master_ar_address(m),
          int_ar_ready_i => master_ar_ready(m),
          int_ar_request_o => master_ar_request(m),
          int_ar_grant_i => master_ar_grant(m),
          int_aw_o => master_aw_address(m),
          int_aw_ready_i => master_aw_ready(m),
          int_aw_request_o => master_aw_request(m),
          int_aw_grant_i => master_aw_grant(m),
          int_w_o => master_w_data(m),
          int_w_ready_i => master_w_ready(m),
          int_w_select_o => master_w_select(m),
          int_r_i => merged_r_data(m),
          int_r_valid_i => merged_r_valid(m),
          int_r_ready_o => master_r_ready(m),
          int_b_i => merged_b_data(m),
          int_b_valid_i => merged_b_valid(m),
          int_b_ready_o => master_b_ready(m)
          );
    end generate;
  end generate;

  -- External slave ports generation
  external_slave_ports: for s in 0 to external_slave_count_c-1 generate
    signal ar_addresses : address_vector(0 to master_count_c-1);
    signal ar_requests : std_ulogic_vector(0 to master_count_c-1);
    signal ar_grants : std_ulogic_vector(0 to master_count_c-1);
    signal aw_addresses : address_vector(0 to master_count_c-1);
    signal aw_requests : std_ulogic_vector(0 to master_count_c-1);
    signal aw_grants : std_ulogic_vector(0 to master_count_c-1);
    signal w_datas : write_data_vector(0 to master_count_c-1);
    signal w_selects : std_ulogic_vector(0 to master_count_c-1);
    signal w_readys : std_ulogic_vector(0 to master_count_c-1);
    signal r_readys : std_ulogic_vector(0 to master_count_c-1);
    signal b_readys : std_ulogic_vector(0 to master_count_c-1);
  begin
    -- Gather signals from all master ports for this slave
    gather_signals: for m in 0 to master_count_c-1 generate
      ar_addresses(m) <= master_ar_address(m);
      ar_requests(m) <= master_ar_request(m)(s);
      master_ar_grant(m)(s) <= ar_grants(m);
      master_ar_ready(m)(s) <= slave_ar_ready(s);

      aw_addresses(m) <= master_aw_address(m);
      aw_requests(m) <= master_aw_request(m)(s);
      master_aw_grant(m)(s) <= aw_grants(m);
      master_aw_ready(m)(s) <= slave_aw_ready(s);

      w_datas(m) <= master_w_data(m);
      w_selects(m) <= master_w_select(m)(s);
      master_w_ready(m)(s) <= w_readys(m);

      r_readys(m) <= slave_r_ready(s)(m);
      b_readys(m) <= slave_b_ready(s)(m);
    end generate;

    direct: if not slave_slice_c generate
      slave_port_inst: work.crossbar_priv.axi4_mm_crossbar_slave_port
        generic map(
          master_config_c => master_config_c,
          slave_config_c => slave_config_c,
          master_count_c => master_count_c,
          aw_tracking_depth_c => aw_tracking_depth_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          int_ar_i => ar_addresses,
          int_ar_ready_o => slave_ar_ready(s),
          int_ar_request_i => ar_requests,
          int_ar_grant_o => ar_grants,
          int_aw_i => aw_addresses,
          int_aw_ready_o => slave_aw_ready(s),
          int_aw_request_i => aw_requests,
          int_aw_grant_o => aw_grants,
          int_w_i => w_datas,
          int_w_ready_o => w_readys,
          int_w_select_i => w_selects,
          int_r_o => slave_r_data(s),
          int_r_valid_o => slave_r_valid(s),
          int_r_ready_i => r_readys,
          int_b_o => slave_b_data(s),
          int_b_valid_o => slave_b_valid(s),
          int_b_ready_i => b_readys,
          ext_o => master_o(s),
          ext_i => master_i(s)
          );
    end generate;

    sliced: if slave_slice_c generate
      signal sliced_m : master_t;
      signal sliced_s : slave_t;
    begin
      slave_port_inst: work.crossbar_priv.axi4_mm_crossbar_slave_port
        generic map(
          master_config_c => master_config_c,
          slave_config_c => slave_config_c,
          master_count_c => master_count_c,
          aw_tracking_depth_c => aw_tracking_depth_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          int_ar_i => ar_addresses,
          int_ar_ready_o => slave_ar_ready(s),
          int_ar_request_i => ar_requests,
          int_ar_grant_o => ar_grants,
          int_aw_i => aw_addresses,
          int_aw_ready_o => slave_aw_ready(s),
          int_aw_request_i => aw_requests,
          int_aw_grant_o => aw_grants,
          int_w_i => w_datas,
          int_w_ready_o => w_readys,
          int_w_select_i => w_selects,
          int_r_o => slave_r_data(s),
          int_r_valid_o => slave_r_valid(s),
          int_r_ready_i => r_readys,
          int_b_o => slave_b_data(s),
          int_b_valid_o => slave_b_valid(s),
          int_b_ready_i => b_readys,
          ext_o => sliced_m,
          ext_i => sliced_s
          );

      slice: nsl_amba.mm_fifo.axi4_mm_slice
        generic map(
          config_c => slave_config_c
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          slave_i => sliced_m,
          slave_o => sliced_s,
          master_o => master_o(s),
          master_i => master_i(s)
          );
    end generate;
  end generate;

  -- Internal error slave generation (conditional)
  gen_error_slave: if has_internal_error_slave_c generate
    signal ar_addresses : address_vector(0 to master_count_c-1);
    signal ar_requests : std_ulogic_vector(0 to master_count_c-1);
    signal ar_grants : std_ulogic_vector(0 to master_count_c-1);
    signal aw_addresses : address_vector(0 to master_count_c-1);
    signal aw_requests : std_ulogic_vector(0 to master_count_c-1);
    signal aw_grants : std_ulogic_vector(0 to master_count_c-1);
    signal w_datas : write_data_vector(0 to master_count_c-1);
    signal w_selects : std_ulogic_vector(0 to master_count_c-1);
    signal w_readys : std_ulogic_vector(0 to master_count_c-1);
    signal r_readys : std_ulogic_vector(0 to master_count_c-1);
    signal b_readys : std_ulogic_vector(0 to master_count_c-1);
  begin
    -- Gather signals from all master ports for error slave
    gather_error_signals: for m in 0 to master_count_c-1 generate
      ar_addresses(m) <= master_ar_address(m);
      ar_requests(m) <= master_ar_request(m)(error_slave_index_c);
      master_ar_grant(m)(error_slave_index_c) <= ar_grants(m);
      master_ar_ready(m)(error_slave_index_c) <= slave_ar_ready(error_slave_index_c);

      aw_addresses(m) <= master_aw_address(m);
      aw_requests(m) <= master_aw_request(m)(error_slave_index_c);
      master_aw_grant(m)(error_slave_index_c) <= aw_grants(m);
      master_aw_ready(m)(error_slave_index_c) <= slave_aw_ready(error_slave_index_c);

      w_datas(m) <= master_w_data(m);
      w_selects(m) <= master_w_select(m)(error_slave_index_c);
      master_w_ready(m)(error_slave_index_c) <= w_readys(m);

      r_readys(m) <= slave_r_ready(error_slave_index_c)(m);
      b_readys(m) <= slave_b_ready(error_slave_index_c)(m);
    end generate;

    error_slave_port_inst: work.crossbar_priv.axi4_mm_crossbar_slave_port
      generic map(
        master_config_c => master_config_c,
        slave_config_c => slave_config_c,
        master_count_c => master_count_c,
        aw_tracking_depth_c => aw_tracking_depth_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        int_ar_i => ar_addresses,
        int_ar_ready_o => slave_ar_ready(error_slave_index_c),
        int_ar_request_i => ar_requests,
        int_ar_grant_o => ar_grants,
        int_aw_i => aw_addresses,
        int_aw_ready_o => slave_aw_ready(error_slave_index_c),
        int_aw_request_i => aw_requests,
        int_aw_grant_o => aw_grants,
        int_w_i => w_datas,
        int_w_ready_o => w_readys,
        int_w_select_i => w_selects,
        int_r_o => slave_r_data(error_slave_index_c),
        int_r_valid_o => slave_r_valid(error_slave_index_c),
        int_r_ready_i => r_readys,
        int_b_o => slave_b_data(error_slave_index_c),
        int_b_valid_o => slave_b_valid(error_slave_index_c),
        int_b_ready_i => b_readys,
        ext_o => error_slave_axi_o,
        ext_i => error_slave_axi_i
        );

    error_slave_inst: work.mm_routing.axi4_mm_error_slave
      generic map(
        config_c => slave_config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        axi_i => error_slave_axi_o,
        axi_o => error_slave_axi_i
        );
  end generate;

  -- R/B response merging: each master receives responses from all slave ports
  -- Since only one slave can have valid asserted for a given master at a time
  -- (due to ID-based routing), we can safely OR the valid signals and mux the data.
  response_merge: process(slave_r_data, slave_r_valid, slave_b_data, slave_b_valid,
                          master_r_ready, master_b_ready)
    variable r_valid_v : std_ulogic;
    variable b_valid_v : std_ulogic;
  begin
    for m in 0 to master_count_c-1 loop
      -- Merge R channel for this master
      merged_r_data(m) <= read_data_defaults(master_config_c);
      r_valid_v := '0';
      for s in 0 to internal_slave_count_c-1 loop
        if slave_r_valid(s)(m) = '1' then
          merged_r_data(m) <= slave_r_data(s);
          r_valid_v := '1';
        end if;
        -- Distribute ready to all slave ports
        slave_r_ready(s)(m) <= master_r_ready(m);
      end loop;
      merged_r_valid(m) <= r_valid_v;

      -- Merge B channel for this master
      merged_b_data(m) <= write_response_defaults(master_config_c);
      b_valid_v := '0';
      for s in 0 to internal_slave_count_c-1 loop
        if slave_b_valid(s)(m) = '1' then
          merged_b_data(m) <= slave_b_data(s);
          b_valid_v := '1';
        end if;
        -- Distribute ready to all slave ports
        slave_b_ready(s)(m) <= master_b_ready(m);
      end loop;
      merged_b_valid(m) <= b_valid_v;
    end loop;
  end process;

end architecture;
