library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_memory, nsl_logic, nsl_bnoc, nsl_clocking;
use nsl_logic.bool.all;
use work.flit.all;
use work.link.all;
use work.rgmii.all;
use nsl_logic.bool.all;

entity rgmii_driver is
  generic(
    rx_clock_delay_ps_c: natural := 0;
    tx_clock_delay_ps_c: natural := 0;
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rgmii_o : out rgmii_io_group_t;
    rgmii_i : in  rgmii_io_group_t;

    mode_i : in link_speed_t;

    rx_sfd_o: out std_ulogic;
    tx_sfd_o: out std_ulogic;

    rx_clock_o : out std_ulogic;
    rx_flit_o : out mii_flit_t;
    
    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in nsl_bnoc.committed.committed_ack;

    tx_i : in nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of rgmii_driver is

  signal tx_prefilled_s: nsl_bnoc.committed.committed_bus;
  signal rx_relax_s: nsl_bnoc.committed.committed_bus;
  signal rx_flit_s, tx_flit_s: mii_flit_t;
  signal rx_sdr_s, tx_sdr_s: rgmii_sdr_io_t;
  signal rx_valid_s, tx_ready_s, rx_clock_s: std_ulogic;
  signal rx_reset_n_s, rx_sfd_s: std_ulogic;

begin

  rx_clock_o <= rx_clock_s;
  rx_flit_o <= rx_flit_s;
  
  -- RX side
  rgmii_rx: work.rgmii.rgmii_rx_driver
    generic map(
      clock_delay_ps_c => rx_clock_delay_ps_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      rx_clock_o => rx_clock_s,

      mode_i => mode_i,
      rgmii_i => rgmii_i,
      sfd_o => rx_sfd_s,

      flit_o => rx_sdr_s,
      valid_o => rx_valid_s
      );

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rx_clock_s,
      data_i => reset_n_i,
      data_o => rx_reset_n_s
      );
  
  sfd: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => rx_clock_s,
      output_clock_i => clock_i,
      input_reset_n_i => rx_reset_n_s,
      tick_i => rx_sfd_s,
      tick_o => rx_sfd_o
      );

  rx_flit_s.data <= rx_sdr_s.data;
  rx_flit_s.valid <= rx_sdr_s.dv;
  rx_flit_s.error <= rx_sdr_s.er;
  
  rx_to_committed: work.flit.mii_flit_to_committed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => rx_flit_s,
      valid_i => rx_valid_s,

      committed_o => rx_relax_s.req,
      committed_i => rx_relax_s.ack
      );

  rx_relax: nsl_bnoc.committed.committed_fifo
    generic map(
      depth_c => 32
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      in_i => rx_relax_s.req,
      in_o => rx_relax_s.ack,
      out_o => rx_o,
      out_i => rx_i
      );
  
  -- TX side
  tx_prefill: nsl_bnoc.committed.committed_prefill_buffer
    generic map(
      prefill_count_c => 16
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      in_i => tx_i,
      in_o => tx_o,
      out_o => tx_prefilled_s.req,
      out_i => tx_prefilled_s.ack
      );
  
  tx_from_committed: work.flit.mii_flit_from_committed
    generic map(
      ipg_c => ipg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      committed_i => tx_prefilled_s.req,
      committed_o => tx_prefilled_s.ack,

      flit_o => tx_flit_s,
      ready_i => tx_ready_s
      );

  tx_sdr_s.data <= tx_flit_s.data;
  tx_sdr_s.dv <= tx_flit_s.valid;
  tx_sdr_s.er <= tx_flit_s.error;

  rgmii_tx: work.rgmii.rgmii_tx_driver
    generic map(
      clock_delay_ps_c => tx_clock_delay_ps_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      mode_i => mode_i,
      flit_i => tx_sdr_s,
      ready_o => tx_ready_s,

      sfd_o => tx_sfd_o,

      rgmii_o => rgmii_o
      );
      
end architecture;
