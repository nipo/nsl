library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

-- Internal details of mm_routing implementation
package crossbar_priv is

  -- Vector types for internal crossbar signals
  type address_vector is array (natural range <>) of work.axi4_mm.address_t;
  type write_data_vector is array (natural range <>) of work.axi4_mm.write_data_t;
  type write_response_vector is array (natural range <>) of work.axi4_mm.write_response_t;
  type read_data_vector is array (natural range <>) of work.axi4_mm.read_data_t;

  -- Master port: handles one external master's connection to the crossbar.
  -- Performs address decode, request generation, and W channel correlation.
  component axi4_mm_crossbar_master_port is
    generic(
      master_config_c : work.axi4_mm.config_t;
      slave_config_c : work.axi4_mm.config_t;
      slave_count_c : positive;
      routing_table_c : work.address.address_vector;
      default_slave_c : natural;
      master_index_c : natural;
      aw_tracking_depth_c : positive := 4;
      max_outstanding_c : positive := 16
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- External master interface (master_config_c)
      ext_i : in work.axi4_mm.master_t;
      ext_o : out work.axi4_mm.slave_t;

      -- Internal crossbar interface (slave_config_c, one set per slave)
      -- AR channel
      int_ar_o : out work.axi4_mm.address_t;
      int_ar_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
      int_ar_request_o : out std_ulogic_vector(0 to slave_count_c-1);
      int_ar_grant_i : in std_ulogic_vector(0 to slave_count_c-1);

      -- AW channel
      int_aw_o : out work.axi4_mm.address_t;
      int_aw_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
      int_aw_request_o : out std_ulogic_vector(0 to slave_count_c-1);
      int_aw_grant_i : in std_ulogic_vector(0 to slave_count_c-1);

      -- W channel (follows AW routing)
      int_w_o : out work.axi4_mm.write_data_t;
      int_w_ready_i : in std_ulogic_vector(0 to slave_count_c-1);
      int_w_select_o : out std_ulogic_vector(0 to slave_count_c-1);

      -- R channel (routed by ID from slave ports)
      int_r_i : in work.axi4_mm.read_data_t;
      int_r_valid_i : in std_ulogic;
      int_r_ready_o : out std_ulogic;

      -- B channel (routed by ID from slave ports)
      int_b_i : in work.axi4_mm.write_response_t;
      int_b_valid_i : in std_ulogic;
      int_b_ready_o : out std_ulogic
      );
  end component;

  -- Slave port: handles one external slave's connection to the crossbar.
  -- Performs arbitration among masters and ID widening/stripping.
  component axi4_mm_crossbar_slave_port is
    generic(
      master_config_c : work.axi4_mm.config_t;
      slave_config_c : work.axi4_mm.config_t;
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
      int_r_o : out work.axi4_mm.read_data_t;
      int_r_valid_o : out std_ulogic_vector(0 to master_count_c-1);
      int_r_ready_i : in std_ulogic_vector(0 to master_count_c-1);

      -- B channel (broadcast to all masters, they filter by ID)
      int_b_o : out work.axi4_mm.write_response_t;
      int_b_valid_o : out std_ulogic_vector(0 to master_count_c-1);
      int_b_ready_i : in std_ulogic_vector(0 to master_count_c-1);

      -- External slave interface (slave_config_c)
      ext_o : out work.axi4_mm.master_t;
      ext_i : in work.axi4_mm.slave_t
      );
  end component;

end package crossbar_priv;
