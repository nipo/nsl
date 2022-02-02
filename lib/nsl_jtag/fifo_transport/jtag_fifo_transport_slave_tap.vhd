library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking, nsl_memory, nsl_logic;

entity jtag_fifo_transport_slave_tap is
  generic(
    width_c : positive;
    status_enable_c : boolean := true;
    -- RX path is critical if we want to speculatively send data.
    -- If depth is only one, a simple cross-region slice is used instead
    rx_fifo_depth_c : positive := 1;
    -- If depth is only one, a simple cross-region slice is used instead
    tx_fifo_depth_c : positive := 1
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

    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_valid_i  : in  std_ulogic;
    tx_ready_o  : out std_ulogic;

    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_valid_o  : out std_ulogic;
    rx_ready_i  : in  std_ulogic
    );
end entity;

architecture beh of jtag_fifo_transport_slave_tap is

  subtype shreg_t is std_ulogic_vector(width_c+2-1 downto 0);
  -- Ready, Valid, Data[width_c]
  
  type regs_t is
  record
    peer_data : std_ulogic_vector(width_c-1 downto 0);
    peer_ready : std_ulogic;
    peer_valid : std_ulogic;

    rxd, txd : std_ulogic_vector(width_c-1 downto 0);
    rxd_used, txd_used : std_ulogic;

    sent_rx_ready, sent_tx_valid : std_ulogic;

    status_shreg : std_ulogic_vector(31 downto 0);
    data_shreg : shreg_t;
  end record;

  signal r, rin: regs_t;

  signal tx_data, rx_data : std_ulogic_vector(width_c-1 downto 0);
  signal tx_ready, tx_valid, rx_valid, rx_ready : std_ulogic;

  signal reset_n, merged_reset_n : std_ulogic;
  signal in_free : integer range 0 to rx_fifo_depth_c;
  signal out_available : integer range 0 to tx_fifo_depth_c;

  constant reg_count_c : integer := nsl_logic.bool.if_else(status_enable_c, 2, 1);
  signal tlr_s, rti_s, update_s, capture_s, shift_s, tdi_s, tck_s: std_ulogic;
  signal tdo_s, selected_s : std_ulogic_vector(0 to reg_count_c-1);

begin

  inst: nsl_hwdep.jtag.jtag_user_tap
    generic map(
      user_port_count_c => reg_count_c
      )
    port map(
      chip_tck_i => chip_tck_i,
      chip_tdi_i => chip_tdi_i,
      chip_tms_i => chip_tms_i,
      chip_tdo_o => chip_tdo_o,

      tdo_i => tdo_s,
      selected_o => selected_s,
      tdi_o => tdi_s,
      run_o => rti_s,
      shift_o => shift_s,
      capture_o => capture_s,
      update_o => update_s,
      tlr_o => tlr_s,
      tck_o => tck_s
      );
  
  merged_reset_n <= (not tlr_s) and reset_n_i;
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => tck_s,
      data_i => merged_reset_n,
      data_o => reset_n
      );

  reset_sync_out: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_i,
      data_i => merged_reset_n,
      data_o => reset_n_o
      );

  tdo_s(0) <= r.data_shreg(0);
  status_io: if status_enable_c
  generate
    tdo_s(1) <= r.status_shreg(0);
  end generate;

  rx_fifo_1: if rx_fifo_depth_c = 1
  generate
    -- Slice one word from jtag clock
    jtag_to_system_fifo: nsl_clocking.interdomain.interdomain_fifo_slice
      generic map(
        data_width_c => width_c
        )
      port map(
        reset_n_i => reset_n,
        clock_i(0) => tck_s,
        clock_i(1) => clock_i,

        in_data_i => rx_data,
        in_valid_i => rx_valid,
        in_ready_o => rx_ready,

        out_data_o => rx_data_o,
        out_ready_i => rx_ready_i,
        out_valid_o => rx_valid_o
        );

    in_free <= 1 when rx_ready = '1' else 0;
  end generate;

  rx_fifo_more: if rx_fifo_depth_c /= 1
  generate
    jtag_to_system_fifo: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => width_c,
        word_count_c => rx_fifo_depth_c,
        clock_count_c => 2
        )
      port map(
        reset_n_i => reset_n,
        clock_i(0) => tck_s,
        clock_i(1) => clock_i,

        in_data_i => rx_data,
        in_valid_i => rx_valid,
        in_ready_o => rx_ready,

        out_data_o => rx_data_o,
        out_ready_i => rx_ready_i,
        out_valid_o => rx_valid_o,

        in_free_o => in_free
        );
  end generate;

  tx_fifo_1: if tx_fifo_depth_c = 1
  generate
    -- Slice one word to jtag clock
    system_to_jtag_fifo: nsl_clocking.interdomain.interdomain_fifo_slice
      generic map(
        data_width_c => width_c
        )
      port map(
        reset_n_i => reset_n,
        clock_i(0) => clock_i,
        clock_i(1) => tck_s,

        in_data_i => tx_data_i,
        in_valid_i => tx_valid_i,
        in_ready_o => tx_ready_o,

        out_data_o => tx_data,
        out_ready_i => tx_ready,
        out_valid_o => tx_valid
        );

    out_available <= 1 when tx_valid = '1' else 0;
  end generate;

  tx_fifo_more: if tx_fifo_depth_c /= 1
  generate
    jtag_to_system_fifo: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => width_c,
        word_count_c => tx_fifo_depth_c,
        clock_count_c => 2
        )
      port map(
        reset_n_i => reset_n,
        clock_i(0) => clock_i,
        clock_i(1) => tck_s,

        in_data_i => tx_data_i,
        in_valid_i => tx_valid_i,
        in_ready_o => tx_ready_o,

        out_data_o => tx_data,
        out_ready_i => tx_ready,
        out_valid_o => tx_valid,

        out_available_min_o => out_available
        );
  end generate;
  
  regs: process(tck_s)
  begin
    if rising_edge(tck_s) then
      r <= rin;
    end if;
  end process;
  
  transition: process(capture_s, in_free, tlr_s, out_available, r,
                      rx_ready, selected_s, tx_data,
                      tx_valid, update_s, shift_s, tdi_s)
  begin
    rin <= r;

    if status_enable_c then
      if selected_s(1) = '1' then
        if capture_s = '1' then
          rin.status_shreg <= std_ulogic_vector(to_unsigned(in_free, 16)
                                                & to_unsigned(out_available, 16));
        elsif shift_s = '1' then
          rin.status_shreg <= tdi_s & r.status_shreg(r.status_shreg'left downto 1);
        end if;
      end if;
    end if;

    if selected_s(0) = '1' then
      if capture_s = '1' then
        rin.data_shreg <= (not r.rxd_used) & r.txd_used & r.txd;
        rin.sent_tx_valid <= r.txd_used;
        rin.sent_rx_ready <= not r.rxd_used;
        rin.peer_ready <= '0';
        rin.peer_valid <= '0';
      elsif shift_s = '1' then
        rin.data_shreg <= tdi_s & r.data_shreg(r.data_shreg'left downto 1);
      end if;

      if update_s = '1' then
        rin.peer_ready <= r.data_shreg(width_c+1);
        rin.peer_valid <= r.data_shreg(width_c);
        rin.peer_data <= r.data_shreg(width_c-1 downto 0);
      end if;
    end if;

    if r.sent_tx_valid = '1' and r.peer_ready = '1' then
      rin.txd_used <= '0';
      rin.sent_tx_valid <= '0';
      rin.peer_ready <= '0';
    end if;

    if r.sent_rx_ready = '1' and r.peer_valid = '1' then
      rin.sent_rx_ready <= '0';
      rin.rxd_used <= '1';
      rin.rxd <= r.peer_data;
      rin.peer_valid <= '0';
    end if;

    if r.rxd_used = '1' and rx_ready = '1' then
      rin.rxd_used <= '0';
    end if;

    if r.txd_used = '0' and tx_valid = '1' then
      rin.txd_used <= '1';
      rin.txd <= tx_data;
    end if;

    if tlr_s = '1' then
      rin.peer_data <= (others => '-');
      rin.txd <= (others => '-');
      rin.rxd <= (others => '-');
      rin.peer_ready <= '0';
      rin.peer_valid <= '0';
      rin.sent_tx_valid <= '0';
      rin.sent_rx_ready <= '0';
      rin.txd_used <= '0';
      rin.rxd_used <= '0';
    end if;
  end process;

  tx_ready <= not r.txd_used;
  rx_valid <= r.rxd_used;
  rx_data <= r.rxd;

end architecture;
