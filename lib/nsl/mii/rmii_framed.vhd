library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.sized.all;
use nsl.framed.all;
use nsl.mii.all;
library util;
use util.sync.all;

entity rmii_framed is
  generic(
    inter_frame : natural := 56;
    mtu: natural := 1024
    );
  port(
    p_resetn    : in std_ulogic;

    p_clk_rmii  : in std_ulogic;
    p_to_mac    : out rmii_datapath;
    p_from_mac  : in  rmii_datapath;

    p_clk_framed   : in std_ulogic;
    p_in_val    : in  nsl.framed.framed_req;
    p_in_ack    : out nsl.framed.framed_ack;
    p_out_val   : out nsl.framed.framed_req;
    p_out_ack   : in  nsl.framed.framed_ack
    );
end entity;

architecture hier of rmii_framed is

  signal s_to_mac_atomic_val : nsl.framed.framed_req;
  signal s_to_mac_atomic_ack : nsl.framed.framed_ack;
  signal s_to_mac_sync_val : nsl.framed.framed_req;
  signal s_to_mac_sync_ack : nsl.framed.framed_ack;
  signal s_from_mac_val : nsl.framed.framed_req;
  signal s_from_mac_ack : nsl.framed.framed_ack;
  
begin

  from_mac: nsl.mii.rmii_to_framed
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk_rmii,
      
      p_rmii_data => p_from_mac,
      p_framed_val => s_from_mac_val,
      p_framed_ack => s_from_mac_ack
      );

  to_mac: nsl.mii.rmii_from_framed
    generic map(
      inter_frame => inter_frame
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk_rmii,
      
      p_rmii_data => p_to_mac,
      p_framed_val => s_to_mac_atomic_val,
      p_framed_ack => s_to_mac_atomic_ack
      );

  to_mac_atomic: nsl.framed.framed_fifo_atomic
    generic map(
      depth => mtu,
      clk_count => 1
      )
    port map(
      p_resetn => p_resetn,
      p_clk(0) => p_clk_rmii,
      p_in_val => s_to_mac_sync_val,
      p_in_ack => s_to_mac_sync_ack,
      p_out_val => s_to_mac_atomic_val,
      p_out_ack => s_to_mac_atomic_ack
      );

  to_mac_resync: nsl.framed.framed_fifo
    generic map(
      depth => 16,
      clk_count => 2
      )
    port map(
      p_resetn => p_resetn,
      p_clk(0) => p_clk_framed,
      p_clk(1) => p_clk_rmii,
      p_in_val => p_in_val,
      p_in_ack => p_in_ack,
      p_out_val => s_to_mac_sync_val,
      p_out_ack => s_to_mac_sync_ack
      );


  from_mac_resync: nsl.framed.framed_fifo
    generic map(
      depth => mtu,
      clk_count => 2
      )
    port map(
      p_resetn => p_resetn,
      p_clk(0) => p_clk_rmii,
      p_clk(1) => p_clk_framed,
      p_in_val => s_from_mac_val,
      p_in_ack => s_from_mac_ack,
      p_out_val => p_out_val,
      p_out_ack => p_out_ack
      );
end;
