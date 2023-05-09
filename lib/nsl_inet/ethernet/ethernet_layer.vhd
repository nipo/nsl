library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ethernet.all;

entity ethernet_layer is
  generic(
    ethertype_c : ethertype_vector;
    -- Flit count to pass through at the start of a frame
    l1_header_length_c : integer := 0;
    min_frame_size_c : natural := 64; --bytes
    mtu_c : natural := 1500;
    filter_inbound_packets_c : boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    to_l3_o : out nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
    to_l3_i : in nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);
    from_l3_i : in nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
    from_l3_o : out nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);

    to_l1_o : out nsl_bnoc.committed.committed_req;
    to_l1_i : in nsl_bnoc.committed.committed_ack;
    from_l1_i : in nsl_bnoc.committed.committed_req;
    from_l1_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of ethernet_layer is

  alias ethertype_l_c : ethertype_vector(0 to ethertype_c'length-1) is ethertype_c;

  signal s_to_l3_index, s_from_l3_index: integer range 0 to ethertype_l_c'length - 1;
  signal s_from_l3_type : ethertype_t;
  signal s_from_l1, s_to_l3, s_to_l3_valid, s_from_l3: nsl_bnoc.committed.committed_bus;
  
begin

  receiver_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 32,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => clock_i,

      p_in_val => from_l1_i,
      p_in_ack => from_l1_o,

      p_out_val => s_from_l1.req,
      p_out_ack => s_from_l1.ack
      );
  
  receiver: work.ethernet.ethernet_receiver
    generic map(
      ethertype_c => ethertype_l_c,
      l1_header_length_c => l1_header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      local_address_i => local_address_i,
      l1_i => s_from_l1.req,
      l1_o => s_from_l1.ack,

      l3_type_index_o => s_to_l3_index,
      l3_o => s_to_l3.req,
      l3_i => s_to_l3.ack
      );

  has_filter: if filter_inbound_packets_c
  generate
    signal s_tmp: nsl_bnoc.committed.committed_bus;
  begin
    filter: nsl_bnoc.committed.committed_filter
      generic map(
        max_size_c => nsl_math.arith.align_up(mtu_c)
        )        
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,
        in_i => s_to_l3.req,
        in_o => s_to_l3.ack,
        out_o => s_tmp.req,
        out_i => s_tmp.ack
        );

    slice: nsl_bnoc.committed.committed_fifo_slice
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,
        in_i => s_tmp.req,
        in_o => s_tmp.ack,
        out_o => s_to_l3_valid.req,
        out_i => s_to_l3_valid.ack
        );        
  end generate;

  no_filter: if not filter_inbound_packets_c
  generate
    s_to_l3_valid.req <= s_to_l3.req;
    s_to_l3.ack <= s_to_l3_valid.ack;
  end generate;

  l3_dispatch: nsl_bnoc.committed.committed_dispatch
    generic map(
      destination_count_c => ethertype_c'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      destination_i => s_to_l3_index,

      in_i => s_to_l3_valid.req,
      in_o => s_to_l3_valid.ack,

      out_o => to_l3_o,
      out_i => to_l3_i
      );

  l3_funnel: nsl_bnoc.committed.committed_funnel
    generic map(
      source_count_c => ethertype_c'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      selected_o => s_from_l3_index,

      in_i => from_l3_i,
      in_o => from_l3_o,

      out_o => s_from_l3.req,
      out_i => s_from_l3.ack
      );

  s_from_l3_type <= ethertype_l_c(s_from_l3_index);
  
  transmitter: work.ethernet.ethernet_transmitter
    generic map(
      l1_header_length_c => l1_header_length_c,
      min_frame_size_c => min_frame_size_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      local_address_i => local_address_i,

      l3_type_i => s_from_l3_type,
      l3_i => s_from_l3.req,
      l3_o => s_from_l3.ack,

      l1_o => to_l1_o,
      l1_i => to_l1_i
      );

end architecture;
