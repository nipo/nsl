library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory, nsl_mii;

entity rmii_framed is
  generic(
    inter_frame : natural := 56;
    mtu: natural := 1024
    );
  port(
    reset_n_i    : in std_ulogic;

    rmii_clock_i  : in std_ulogic;
    rmii_o    : out nsl_mii.mii.rmii_datapath;
    rmii_i  : in  nsl_mii.mii.rmii_datapath;

    framed_clock_i   : in std_ulogic;
    to_rmii_i    : in  nsl_bnoc.framed.framed_req;
    to_rmii_o    : out nsl_bnoc.framed.framed_ack;
    from_rmii_o   : out nsl_bnoc.framed.framed_req;
    from_rmii_i   : in  nsl_bnoc.framed.framed_ack
    );
end entity;

architecture hier of rmii_framed is

  signal s_to_mac_atomic : nsl_bnoc.framed.framed_bus;
  signal s_to_mac_sync : nsl_bnoc.framed.framed_bus;
  signal s_from_mac : nsl_bnoc.framed.framed_bus;
  
begin

  from_mac: nsl_mii.framed.rmii_to_framed
    port map(
      reset_n_i => reset_n_i,
      clock_i => rmii_clock_i,
      
      rmii_i => rmii_i,
      framed_o => s_from_mac.req
      );

  to_mac: nsl_mii.framed.rmii_from_framed
    generic map(
      inter_frame => inter_frame
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => rmii_clock_i,
      
      rmii_o => rmii_o,
      framed_i => s_to_mac_atomic.req,
      framed_o => s_to_mac_atomic.ack
      );

  to_mac_atomic: nsl_bnoc.framed.framed_fifo_atomic
    generic map(
      depth => mtu,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => rmii_clock_i,
      p_in_val => s_to_mac_sync.req,
      p_in_ack => s_to_mac_sync.ack,
      p_out_val => s_to_mac_atomic.req,
      p_out_ack => s_to_mac_atomic.ack
      );

  to_mac_resync: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 16,
      clk_count => 2
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => framed_clock_i,
      p_clk(1) => rmii_clock_i,
      p_in_val => to_rmii_i,
      p_in_ack => to_rmii_o,
      p_out_val => s_to_mac_sync.req,
      p_out_ack => s_to_mac_sync.ack
      );

  from_mac_resync: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => mtu,
      clk_count => 2
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => rmii_clock_i,
      p_clk(1) => framed_clock_i,
      p_in_val => s_from_mac.req,
      p_in_ack => open,
      p_out_val => from_rmii_o,
      p_out_ack => from_rmii_i
      );
end;
