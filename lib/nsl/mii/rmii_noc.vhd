library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.flit.all;
use nsl.fifo.all;
use nsl.mii.all;

entity rmii_noc is
  generic(
    inter_frame : natural := 56
    );
  port(
    p_resetn    : in std_ulogic;

    p_clk_rmii  : in std_ulogic;
    p_to_mac    : out rmii_datapath;
    p_from_mac  : in  rmii_datapath;

    p_clk_noc   : in std_ulogic;
    p_in_val    : in  nsl.flit.flit_cmd;
    p_in_ack    : out nsl.flit.flit_ack;
    p_out_val   : out nsl.flit.flit_cmd;
    p_out_ack   : in  nsl.flit.flit_ack
    );
end entity;

architecture hier of rmii_noc is

  signal s_to_mac_framed_val : nsl.fifo.fifo_framed_cmd;
  signal s_to_mac_framed_ack : nsl.fifo.fifo_framed_rsp;
  signal s_to_mac_atomic_val : nsl.fifo.fifo_framed_cmd;
  signal s_to_mac_atomic_ack : nsl.fifo.fifo_framed_rsp;
  signal s_to_mac_noc_val : nsl.fifo.fifo_framed_cmd;
  signal s_to_mac_noc_ack : nsl.fifo.fifo_framed_rsp;
  signal s_from_mac_mii_val : nsl.fifo.fifo_framed_cmd;
  signal s_from_mac_mii_ack : nsl.fifo.fifo_framed_rsp;
  signal s_from_mac_noc_val : nsl.fifo.fifo_framed_cmd;
  signal s_from_mac_noc_ack : nsl.fifo.fifo_framed_rsp;

  signal s_resetn_rmii : std_ulogic;
  signal s_resetn_noc : std_ulogic;
  
begin

  reset_sync_rmii: nsl.util.reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_resetn_sync => s_resetn_rmii,
      p_clk => p_clk_rmii
      );

  reset_sync_noc: nsl.util.reset_synchronizer
    port map(
      p_resetn => p_resetn,
      p_resetn_sync => s_resetn_noc,
      p_clk => p_clk_noc
      );

  mii_to_framed: nsl.mii.rmii_to_framed
    port map(
      p_resetn => s_resetn_rmii,
      p_clk => p_clk_rmii,
      
      p_rmii_data => p_from_mac,
      p_framed_val => s_from_mac_mii_val,
      p_framed_ack => s_from_mac_mii_ack
      );

  mii_from_framed: nsl.mii.rmii_from_framed
    generic map(
      inter_frame => inter_frame
      )
    port map(
      p_resetn => s_resetn_rmii,
      p_clk => p_clk_rmii,
      
      p_rmii_data => p_to_mac,
      p_framed_val => s_to_mac_atomic_val,
      p_framed_ack => s_to_mac_atomic_ack
      );

  mii_atomic_from_framed: nsl.fifo.fifo_framed_atomic
    generic map(
      depth => 256
      )
    port map(
      p_resetn => s_resetn_rmii,
      p_clk => p_clk_rmii,

      p_in_val => s_to_mac_framed_val,
      p_in_ack => s_to_mac_framed_ack,
      p_out_val => s_to_mac_atomic_val,
      p_out_ack => s_to_mac_atomic_ack
      );
  
  mii_to_noc_fifo: nsl.fifo.fifo_framed_async
    generic map(
      depth => 256
      )
    port map(
      p_resetn => p_resetn,

      p_in_clk => p_clk_rmii,
      p_in_val => s_from_mac_mii_val,
      p_in_ack => s_from_mac_mii_ack,

      p_out_clk => p_clk_noc,
      p_out_val => s_from_mac_noc_val,
      p_out_ack => s_from_mac_noc_ack
      );

  noc_to_mii_fifo: nsl.fifo.fifo_framed_async
    generic map(
      depth => 8
      )
    port map(
      p_resetn => p_resetn,

      p_in_clk => p_clk_rmii,
      p_in_val => s_to_mac_noc_val,
      p_in_ack => s_to_mac_noc_ack,

      p_out_clk => p_clk_noc,
      p_out_val => s_to_mac_framed_val,
      p_out_ack => s_to_mac_framed_ack
      );
      
  to_flit: nsl.flit.flit_from_framed
    generic map(
      data_depth => 256,
      txn_depth => 1
      )
    port map(
      p_resetn => s_resetn_noc,
      p_clk => p_clk_noc,
      p_in_val => s_from_mac_noc_val,
      p_in_ack => s_from_mac_noc_ack,
      p_out_val => p_out_val,
      p_out_ack => p_out_ack
      );
  
  from_flit: nsl.flit.flit_to_framed
    port map(
      p_resetn => s_resetn_noc,
      p_clk => p_clk_noc,
      p_out_val => s_to_mac_noc_val,
      p_out_ack => s_to_mac_noc_ack,
      p_in_val => p_in_val,
      p_in_ack => p_in_ack
      );

end;
