library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

-- Bnoc framed abstraction. A framed interface is a fifo with data and
-- frame boundary information. Frame boundary is expressed with the
-- help of an additional line that is asserted on the last flit of a
-- frame.
package framed is

  subtype framed_data_t is std_ulogic_vector(7 downto 0);

  type framed_req_t is record
    data : framed_data_t;
    last : std_ulogic;
    valid  : std_ulogic;
  end record;

  type framed_ack_t is record
    ready  : std_ulogic;
  end record;

  type framed_bus_t is record
    req: framed_req_t;
    ack: framed_ack_t;
  end record;

  subtype framed_req is framed_req_t;
  subtype framed_ack is framed_ack_t;
  subtype framed_bus is framed_bus_t;

  function framed_flit(data: framed_data_t;
                       last: boolean := false;
                       valid: boolean := true) return framed_req_t;

  function framed_accept(ready: boolean := true) return framed_ack_t;

  constant framed_req_idle_c : framed_req_t := (data => "--------",
                                              last => '-',
                                              valid => '0');
  constant framed_ack_idle_c : framed_ack_t := (ready => '0');
  constant framed_ack_blackhole_c : framed_ack_t := (ready => '1');

  type framed_req_array is array(natural range <>) of framed_req_t;
  type framed_ack_array is array(natural range <>) of framed_ack_t;
  type framed_bus_array is array(natural range <>) of framed_bus_t;
  subtype framed_req_vector is framed_req_array;
  subtype framed_ack_vector is framed_ack_array;
  subtype framed_bus_vector is framed_bus_array;

  component framed_fifo is
    generic(
      depth      : natural;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req_t;
      p_in_ack   : out framed_ack_t;

      p_out_val   : out framed_req_t;
      p_out_ack   : in framed_ack_t
      );
  end component;

  component framed_granted_gate is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      request_o   : out std_ulogic;
      grant_i     : in  std_ulogic;
      busy_o      : out std_ulogic;

      in_cmd_i   : in  framed_req_t;
      in_cmd_o   : out framed_ack_t;
      in_rsp_o   : out framed_req_t;
      in_rsp_i   : in  framed_ack_t;

      out_cmd_o  : out framed_req_t;
      out_cmd_i  : in  framed_ack_t;
      out_rsp_i  : in  framed_req_t;
      out_rsp_o  : out framed_ack_t
      );
  end component;

  component framed_gate_arbitrer is
    generic(
      gate_count_c : integer
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      request_i   : in  std_ulogic_vector(0 to gate_count_c-1);
      grant_o     : out std_ulogic_vector(0 to gate_count_c-1);
      busy_i      : in  std_ulogic_vector(0 to gate_count_c-1);

      selected_o  : out unsigned;
      request_o   : out std_ulogic;
      grant_i     : in  std_ulogic;
      busy_o      : out std_ulogic
      );
  end component;

  component framed_fifo_slice is
    port(
      reset_n_i  : in  std_ulogic;
      clock_i    : in  std_ulogic;

      in_i   : in framed_req_t;
      in_o   : out framed_ack_t;

      out_o   : out framed_req_t;
      out_i   : in framed_ack_t
      );
  end component;

  component framed_fifo_atomic is
    generic(
      depth : natural;
      txn_depth : natural := 4;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req_t;
      p_in_ack   : out framed_ack_t;

      p_out_val   : out framed_req_t;
      p_out_ack   : in framed_ack_t
      );
  end component;

  component framed_arbitrer is
    generic(
      source_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_selected : out unsigned(nsl_math.arith.log2(source_count)-1 downto 0);
      p_request : out std_ulogic;
      p_grant : in std_ulogic := '1';
      
      p_cmd_val   : in framed_req_array(0 to source_count - 1);
      p_cmd_ack   : out framed_ack_array(0 to source_count - 1);
      p_rsp_val   : out framed_req_array(0 to source_count - 1);
      p_rsp_ack   : in framed_ack_array(0 to source_count - 1);

      p_target_cmd_val   : out framed_req_t;
      p_target_cmd_ack   : in framed_ack_t;
      p_target_rsp_val   : in framed_req_t;
      p_target_rsp_ack   : out framed_ack_t
      );
  end component;

  component framed_funnel is
    generic(
      source_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i : in std_ulogic := '1';
      selected_o  : out natural range 0 to source_count_c - 1;
      
      in_i   : in framed_req_array(0 to source_count_c - 1);
      in_o   : out framed_ack_array(0 to source_count_c - 1);

      out_o   : out framed_req_t;
      out_i   : in framed_ack_t
      );
  end component;

  component framed_matrix is
    generic(
      source_count_c : natural;
      destination_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      in_i   : in framed_req_array(0 to source_count_c - 1);
      in_o   : out framed_ack_array(0 to source_count_c - 1);

      source_i: in nsl_math.int_ext.integer_vector(0 to destination_count_c - 1);
      out_o   : out framed_req_array(0 to destination_count_c - 1);
      out_i   : in framed_ack_array(0 to destination_count_c - 1)
      );
  end component;

  component framed_dispatch is
    generic(
      destination_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i : in std_ulogic := '1';
      destination_i  : in natural range 0 to destination_count_c - 1;
      
      in_i   : in framed_req_t;
      in_o   : out framed_ack_t;

      out_o   : out framed_req_array(0 to destination_count_c - 1);
      out_i   : in framed_ack_array(0 to destination_count_c - 1)
      );
  end component;

  component framed_gate is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i   : in std_ulogic;

      in_i   : in framed_req_t;
      in_o   : out framed_ack_t;
      out_o   : out framed_req_t;
      out_i   : in framed_ack_t
      );
  end component;

  -- This component creates a framed context from a fifo + flush
  -- operation.
  --
  -- Flush lags one cycle after matching data cycle,
  -- whatever the data flowing through during this later cycle.
  --
  -- This creates three frames containing data [0, 1, 2] on the output:
  --            _   _   _   _   _   _   _   _   _   _   _   _   _   _
  -- clock_i \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \
  --         _______________________________________________
  -- ready_o                                                \_________
  --             ___________         _______________________     _____
  -- valid_i ___/           \_______/                       \___/
  -- data_i  ---X 0 X 1 X 2 X-------X 0 X 1 X 2 X 0 X 1 X 2 X---X 8 X
  --                             ___             ___             ___
  -- flush_i ___________________/   \___________/   \___________/   \_
  --
  component framed_committer is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      data_i : in framed_data_t;
      valid_i : in std_ulogic;
      ready_o : out std_ulogic;

      flush_i : in std_ulogic;

      req_o : out framed_req_t;
      ack_i : in framed_ack_t
      );
  end component;

  component framed_framer is
    generic(
      timeout_c : natural;
      max_length_c : natural := 1024
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic;

      pipe_i   : in  nsl_bnoc.pipe.pipe_req_t;
      pipe_o   : out nsl_bnoc.pipe.pipe_ack_t;

      frame_o  : out framed_req_t;
      frame_i  : in framed_ack_t
      );
  end component;

  component framed_unframer is
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic;

      frame_i  : in framed_req_t;
      frame_o  : out framed_ack_t;

      pipe_o   : out nsl_bnoc.pipe.pipe_req_t;
      pipe_i   : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;

  -- Generic router for framed (and specializations like
  -- framed/routed/committed) network where frame at input has
  -- in_header_count_c bytes of header used for routing.
  --
  -- Routing decision is external to this module, using route_* ports.
  -- When forwarded, output frame has input header replaced with
  -- passed header of out_header_count_c bytes.
  --
  -- If intention is to forward header as-is, parent should set
  -- out_header_count_c = in_header_count_c and connect route_header_o
  -- to route_header_i.
  component framed_router is
    generic(
      in_count_c : natural;
      out_count_c : natural;
      in_header_count_c : natural := 0;
      out_header_count_c : natural := 0
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic;

      in_i      : in framed_req_array(0 to in_count_c-1);
      in_o      : out framed_ack_array(0 to in_count_c-1);

      out_o     : out framed_req_array(0 to out_count_c-1);
      out_i     : in framed_ack_array(0 to out_count_c-1);

    route_valid_o       : out std_ulogic;
    route_header_o      : out byte_string(0 to in_header_count_c-1);
    route_source_o      : out natural range 0 to in_count_c-1;

    route_ready_i       : in  std_ulogic := '1';
    route_header_i      : in  byte_string(0 to out_header_count_c-1) := (others => x"00");
    route_destination_i : in  natural range 0 to out_count_c-1;
    route_drop_i        : in std_ulogic := '0'
      );
  end component;

end package framed;

package body framed is

  function framed_flit(data: framed_data_t;
                       last: boolean := false;
                       valid: boolean := true) return framed_req_t
  is
  begin
    if not valid then
      return (valid => '0', data => "--------", last => '-');
    elsif last then
      return (valid => '1', data => data, last => '1');
    else
      return (valid => '1', data => data, last => '0');
    end if;
  end function;

  function framed_accept(ready: boolean := true) return framed_ack_t
  is
  begin
    if ready then
      return (ready => '1');
    else
      return (ready => '0');
    end if;
  end function;

end package body;
