library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking, nsl_memory;

entity jtag_fifo_transport_slave is
  generic(
    width_c : positive;
    data_reg_no_c : integer;
    -- if < 0, free register is disabled
    status_reg_no_c : integer := -1;
    rx_fifo_depth_c : positive := 1;
    tx_fifo_depth_c : positive := 1
    );
  port(
    -- Clocks the fifo
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

architecture beh of jtag_fifo_transport_slave is

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
  end record;

  signal r, rin: regs_t;
  
  signal jtag_word_in_valid, jtag_word_out_ready : std_ulogic;
  signal jtag_word_in, jtag_word_out : shreg_t;

  signal tx_data, rx_data : std_ulogic_vector(width_c-1 downto 0);
  signal tx_ready, tx_valid, rx_valid, rx_ready : std_ulogic;

  signal jtag_clock, tlr, reset_n, merged_reset_n : std_ulogic;
  signal in_free : integer range 0 to rx_fifo_depth_c;
  signal out_available : integer range 0 to tx_fifo_depth_c;
  
begin

  merged_reset_n <= (not tlr) and reset_n_i;
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => jtag_clock,
      data_i => merged_reset_n,
      data_o => reset_n
      );

  reset_sync_out: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_i,
      data_i => merged_reset_n,
      data_o => reset_n_o
      );

  shreg: nsl_hwdep.jtag.jtag_reg
    generic map(
      width_c => shreg_t'length,
      id_c => data_reg_no_c
      )
    port map(
      clock_o => jtag_clock,
      tlr_o => tlr,

      data_i => jtag_word_out,
      capture_o => jtag_word_out_ready,

      data_o => jtag_word_in,
      update_o => jtag_word_in_valid
      );

  rx_fifo_1: if rx_fifo_depth_c = 1
  generate
    -- Slice one word from jtag clock
    jtag_to_system_fifo: nsl_clocking.interdomain.interdomain_fifo_slice
      generic map(
        data_width_c => width_c
        )
      port map(
        reset_n_i => reset_n,
        clock_i(0) => jtag_clock,
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
        clock_i(0) => jtag_clock,
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
        clock_i(1) => jtag_clock,

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
        clock_i(1) => jtag_clock,

        in_data_i => tx_data_i,
        in_valid_i => tx_valid_i,
        in_ready_o => tx_ready_o,

        out_data_o => tx_data,
        out_ready_i => tx_ready,
        out_valid_o => tx_valid,

        out_available_min_o => out_available
        );
  end generate;

  status_reg: if status_reg_no_c >= 0
  generate
    signal in_free_uns : unsigned(15 downto 0);
    signal out_available_uns : unsigned(15 downto 0);
    signal data : std_ulogic_vector(31 downto 0);
  begin

    in_free_uns <= to_unsigned(in_free, in_free_uns'length);
    out_available_uns <= to_unsigned(out_available, out_available_uns'length);
    data <= std_ulogic_vector(in_free_uns & out_available_uns);

    status_reg: nsl_hwdep.jtag.jtag_reg
      generic map(
        width_c => data'length,
        id_c => status_reg_no_c
        )
      port map(
        data_i => data
        );
  end generate;
  
  regs: process(jtag_clock)
  begin
    if rising_edge(jtag_clock) then
      r <= rin;
    end if;
  end process;

  transition: process(r, jtag_word_out_ready,
                      jtag_word_in, jtag_word_in_valid,
                      tx_data, tx_valid, rx_ready, tlr)
  begin
    rin <= r;

    if jtag_word_out_ready = '1' then
      rin.sent_tx_valid <= r.txd_used;
      rin.sent_rx_ready <= not r.rxd_used;
      rin.peer_ready <= '0';
      rin.peer_valid <= '0';
    end if;

    if jtag_word_in_valid = '1' then
      rin.peer_ready <= jtag_word_in(width_c+1);
      rin.peer_valid <= jtag_word_in(width_c);
      rin.peer_data <= jtag_word_in(width_c-1 downto 0);
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

    if tlr = '1' then
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

  jtag_word_out <= (not r.rxd_used) & r.txd_used & r.txd;
  
end architecture;
