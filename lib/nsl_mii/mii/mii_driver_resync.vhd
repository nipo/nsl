library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_memory, nsl_logic, nsl_bnoc, nsl_clocking;
use nsl_logic.bool.all;
use nsl_mii.mii.all;
use nsl_logic.bool.all;

entity mii_driver_resync is
  generic(
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    mii_o : out mii_m2p;
    mii_i : in  mii_p2m;

    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in nsl_bnoc.committed.committed_ack;

    tx_i : in nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mii_driver_resync is

  constant resync_depth_c : integer := 8;

  signal rx_flit_s, tx_flit_s, tx_resynced_flit_s: mii_flit_t;
  signal tx_data_s: std_ulogic_vector(3 downto 0);
  signal rx_valid_s, tx_flit_pop_s: std_ulogic;
  signal tx_clock_s, tx_reset_n_s : std_ulogic;
  signal rx_clock_s, rx_reset_n_s : std_ulogic;

  type mii_p2m_pipe_t is array (integer range <>) of mii_rx_p2m;

  type rx_state_t is (
    RX_INTERFRAME,
    RX_PREAMBLE,
    RX_FRAME
    );
  
  type rx_regs_t is
  record
    pipe: mii_p2m_pipe_t(0 to 2);

    is_msb: boolean;
    state: rx_state_t;
    
    flit : mii_flit_t;
    flit_valid : std_ulogic;
  end record;
  
  type tx_regs_t is
  record
    flit: mii_flit_t;
    is_msb: std_ulogic;
  end record;

  signal rx_r, rx_rin: rx_regs_t;
  signal tx_r, tx_rin: tx_regs_t;

begin

  -- RX Side
  rx_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rx_clock_s,
      data_i => reset_n_i,
      data_o => rx_reset_n_s
      );
  
  rx_regs: process(rx_clock_s, rx_reset_n_s) is
  begin
    if rising_edge(rx_clock_s) then
      rx_r <= rx_rin;
    end if;

    if rx_reset_n_s = '0' then
      rx_r.state <= RX_INTERFRAME;
      rx_r.is_msb <= false;
    end if;
  end process;

  rx_transition: process(rx_r, mii_i) is
  begin
    rx_rin <= rx_r;

    rx_rin.pipe <= rx_r.pipe(1 to 2) & mii_i.rx;

    -- One cycle out of 2 makes flit valid
    rx_rin.is_msb <= not rx_r.is_msb;
    rx_rin.flit_valid <= to_logic(rx_r.is_msb);

    -- Merge two consecutive cycles
    rx_rin.flit.data <= rx_r.pipe(1).d & rx_r.pipe(0).d;
    rx_rin.flit.valid <= rx_r.pipe(0).dv and rx_r.pipe(1).dv;
    rx_rin.flit.error <= rx_r.pipe(0).er or rx_r.pipe(1).er;

    case rx_r.state is
      when RX_INTERFRAME =>
        if rx_r.pipe(0).dv = '1' and rx_r.pipe(1).dv = '1' then
          rx_rin.state <= RX_PREAMBLE;
        end if;

      when RX_PREAMBLE =>
        if rx_r.pipe(0).dv = '1' and rx_r.pipe(1).dv = '1' and
          rx_r.pipe(0).d = x"5" and rx_r.pipe(1).d = x"d" then
          rx_rin.state <= RX_FRAME;
          rx_rin.is_msb <= false;
          rx_rin.flit_valid <= '1';
        end if;

      when RX_FRAME =>
        null;
    end case;

    -- Common
    if rx_r.pipe(0).dv = '0' and rx_r.pipe(1).dv = '0' then
      rx_rin.state <= RX_INTERFRAME;
    end if;
  end process;            
  
  rx_cross_domain: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 10,
      word_count_c => resync_depth_c,
      output_slice_c => false,
      input_slice_c => false,
      clock_count_c => 2
      )
    port map(
      reset_n_i => rx_reset_n_s,
      clock_i(0) => rx_clock_s,
      clock_i(1) => clock_i,

      out_data_o(7 downto 0) => rx_flit_s.data,
      out_data_o(8) => rx_flit_s.valid,
      out_data_o(9) => rx_flit_s.error,
      out_ready_i => '1',
      out_valid_o => rx_valid_s,

      in_data_i(7 downto 0) => rx_r.flit.data,
      in_data_i(8) => rx_r.flit.valid,
      in_data_i(9) => rx_r.flit.error,
      in_valid_i => rx_r.flit_valid
      );

  rx_clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => mii_i.rx.clk,
      clock_o => rx_clock_s
      );

  rx_to_committed: work.mii.mii_flit_to_committed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => rx_flit_s,
      valid_i => rx_valid_s,

      committed_o => rx_o,
      committed_i => rx_i
      );
  
  -- TX side
  tx_from_committed: work.mii.mii_flit_from_committed
    generic map(
      ipg_c => ipg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      committed_i => tx_i,
      committed_o => tx_o,

      flit_o => tx_flit_s,
      ready_i => tx_flit_pop_s
      );

  tx_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => tx_clock_s,
      data_i => reset_n_i,
      data_o => tx_reset_n_s
      );
  
  regs: process(tx_clock_s, tx_reset_n_s) is
  begin
    if rising_edge(tx_clock_s) then
      tx_r <= tx_rin;
    end if;

    if tx_reset_n_s = '0' then
      tx_r.is_msb <= '0';
    end if;
  end process;

  transition: process(tx_r, tx_resynced_flit_s) is
  begin
    tx_rin <= tx_r;

    tx_rin.is_msb <= not tx_r.is_msb;
    if tx_r.is_msb = '1' then
      tx_rin.flit <= tx_resynced_flit_s;
    end if;
  end process;

  mii_o.tx.d <= tx_r.flit.data(7 downto 4)
                when tx_r.is_msb = '1' else tx_r.flit.data(3 downto 0);
  mii_o.tx.en <= tx_r.flit.valid;
  mii_o.tx.er <= tx_r.flit.error;

  tx_cross_domain: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 10,
      word_count_c => resync_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => tx_reset_n_s,
      clock_i(0) => clock_i,
      clock_i(1) => tx_clock_s,

      in_data_i(7 downto 0) => tx_flit_s.data,
      in_data_i(8) => tx_flit_s.valid,
      in_data_i(9) => tx_flit_s.error,
      in_valid_i => '1',
      in_ready_o => tx_flit_pop_s,

      out_data_o(7 downto 0) => tx_resynced_flit_s.data,
      out_data_o(8) => tx_resynced_flit_s.valid,
      out_data_o(9) => tx_resynced_flit_s.error,
      out_ready_i => tx_r.is_msb
      );

  tx_clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => mii_i.tx.clk,
      clock_o => tx_clock_s
      );
      
end architecture;
