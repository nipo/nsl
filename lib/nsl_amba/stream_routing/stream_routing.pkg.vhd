library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

package stream_routing is

  component axi4_stream_funnel is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      source_count_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_vector(0 to source_count_c-1);
      in_o : out slave_vector(0 to source_count_c-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  component axi4_stream_dispatch is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      destination_count_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to destination_count_c-1);
      out_i : in slave_vector(0 to destination_count_c-1)
      );
  end component;

  -- Multi-input, multi-output router with header-based routing.
  -- Extracts fixed-length header from input frames, presents to external
  -- routing logic, then inserts output header and forwards data to
  -- selected output port.
  component axi4_stream_router is
    generic(
      config_c : config_t;
      in_count_c : positive;
      out_count_c : positive;
      in_header_length_c : natural := 0;
      out_header_length_c : natural := 0
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic;

      in_i      : in master_vector(0 to in_count_c-1);
      in_o      : out slave_vector(0 to in_count_c-1);

      out_o     : out master_vector(0 to out_count_c-1);
      out_i     : in slave_vector(0 to out_count_c-1);

      route_valid_o       : out std_ulogic;
      route_header_o      : out byte_string(0 to in_header_length_c-1);
      route_source_o      : out natural range 0 to in_count_c-1;

      route_ready_i       : in  std_ulogic := '1';
      route_header_i      : in  byte_string(0 to out_header_length_c-1) := (others => x"00");
      route_destination_i : in  natural range 0 to out_count_c-1 := 0;
      route_drop_i        : in std_ulogic := '0'
      );
  end component;

end package stream_routing;
