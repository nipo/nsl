library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_data, nsl_bnoc, nsl_hwdep, nsl_clocking, nsl_memory;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

entity jtag_continuous_transport_tap is
  generic(
    tx_fifo_depth_c : natural := 256;
    rx_fifo_depth_c : natural := 256
    );
  port(
    chip_tck_i : in std_ulogic := '0';
    chip_tms_i : in std_ulogic := '0';
    chip_tdi_i : in std_ulogic := '0';
    chip_tdo_o : out std_ulogic;

    -- Clocks the fifo, asynchronous to TCK of user reg
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;
    reset_n_o   : out std_ulogic;

    tx_i : in nsl_bnoc.framed.framed_req;
    tx_o : out nsl_bnoc.framed.framed_ack;

    rx_o : out nsl_bnoc.framed.framed_req;
    rx_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of jtag_continuous_transport_tap is

  signal tlr_s, rti_s, update_s, capture_s, shift_s, tdi_s,
    tck_s, tdo_s, selected_s: std_ulogic;
  signal reset_n_s, merged_reset_n_s : std_ulogic;

  signal rx_fifo_free_s : integer range 0 to rx_fifo_depth_c;
  signal tx_fifo_fill_s : integer range 0 to tx_fifo_depth_c;

  signal rx_valid_s, rx_last_s, tx_valid_s, tx_ready_s, tx_last_s : std_ulogic;
  signal rx_data_s, tx_data_s : byte;
  signal rx_free_s, tx_fillness_s : unsigned(credit_bits_c-1 downto 0);
  
begin

  rx_free_s <= to_unsigned(rx_fifo_free_s, rx_free_s'length);
  tx_fillness_s <= to_unsigned(tx_fifo_fill_s, tx_fillness_s'length);
  reset_n_o <= not tlr_s;

  inst: nsl_hwdep.jtag.jtag_user_tap
    generic map(
      user_port_count_c => 1
      )
    port map(
      chip_tck_i => chip_tck_i,
      chip_tdi_i => chip_tdi_i,
      chip_tms_i => chip_tms_i,
      chip_tdo_o => chip_tdo_o,

      tdo_i(0) => tdo_s,
      selected_o(0) => selected_s,
      tdi_o => tdi_s,
      run_o => rti_s,
      shift_o => shift_s,
      capture_o => capture_s,
      update_o => update_s,
      tlr_o => tlr_s,
      tck_o => tck_s
      );
  
  merged_reset_n_s <= (not tlr_s) and reset_n_i;
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => tck_s,
      data_i => merged_reset_n_s,
      data_o => reset_n_s
      );

  core: work.continuous_transport.continuous_transport_core
    port map(
    clock_i   => tck_s,
    reset_n_i => "not"(tlr_s),

    shift_i   => shift_s,
    capture_i => capture_s,
    update_i  => update_s,
    tdi_i     => tdi_s,
    tdo_o     => tdo_s,

    rx_data_o  => rx_data_s,
    rx_last_o  => rx_last_s,
    rx_valid_o => rx_valid_s,
    rx_free_i  => rx_free_s,

    tx_data_i  => tx_data_s,
    tx_last_i  => tx_last_s,
    tx_valid_i => tx_valid_s,
    tx_ready_o => tx_ready_s,
    tx_level_i => tx_fillness_s
    );

  jtag_to_system_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => rx_fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => tck_s,
      clock_i(1) => clock_i,

      out_data_o(8) => rx_o.last,
      out_data_o(7 downto 0) => rx_o.data,
      out_valid_o => rx_o.valid,
      out_ready_i => rx_i.ready,

      in_data_i(8) => rx_last_s,
      in_data_i(7 downto 0) => rx_data_s,
      in_valid_i => rx_valid_s,

      in_free_o => rx_fifo_free_s
      );

  system_to_jtag_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => tx_fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => clock_i,
      clock_i(1) => tck_s,

      in_data_i(8) => tx_i.last,
      in_data_i(7 downto 0) => tx_i.data,
      in_valid_i => tx_i.valid,
      in_ready_o => tx_o.ready,

      out_available_min_o => tx_fifo_fill_s,

      out_data_o(8) => tx_last_s,
      out_data_o(7 downto 0) => tx_data_s,
      out_ready_i => tx_ready_s,
      out_valid_o => tx_valid_s
      );
  
end architecture;
