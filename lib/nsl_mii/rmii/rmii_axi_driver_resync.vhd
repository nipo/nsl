library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_memory, nsl_logic, nsl_amba, nsl_clocking;
use nsl_logic.bool.all;
use work.flit.all;
use work.rmii.all;
use nsl_logic.bool.all;
use work.link.all;

entity rmii_axi_driver_resync is
  generic(
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rmii_ref_clock_i: in std_ulogic;
    rmii_o : out rmii_m2p;
    rmii_i : in  rmii_p2m;

    link_speed_i: in link_speed_t := LINK_SPEED_100;

    tx_sfd_o : out std_ulogic;
    rx_sfd_o : out std_ulogic;

    rx_o : out nsl_amba.axi4_stream.master_t;
    rx_i : in  nsl_amba.axi4_stream.slave_t;

    tx_i : in  nsl_amba.axi4_stream.master_t;
    tx_o : out nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of rmii_axi_driver_resync is

  constant resync_depth_c : integer := 8;
  
  signal rx_flit_s, tx_flit_s, tx_resynced_flit_s: mii_flit_t;
  signal tx_data_s: std_ulogic_vector(1 downto 0);
  signal rx_valid_s, tx_flit_pop_s, tx_ready_s: std_ulogic;
  signal rmii_reset_n_s: std_ulogic;
  signal s_rx_flit_complete : std_ulogic;
  signal rx_sfd_s, tx_sfd_s : std_ulogic;

  type rmii_p2m_pipe_t is array (integer range <>) of rmii_p2m;

  type rx_state_t is (
    RX_INTERFRAME,
    RX_PREAMBLE,
    RX_FRAME
    );
  
  type rx_regs_t is
  record
    pipe: rmii_p2m_pipe_t(0 to 4);

    is_sfd: boolean;
    dibit_to_go: unsigned(1 downto 0);
    state: rx_state_t;
    
    flit : mii_flit_t;
  end record;
  
  type tx_regs_t is
  record
    flit: mii_flit_t;
    dibit_to_go: unsigned(1 downto 0);
    new_frame, is_sfd: boolean;
  end record;
  
  type regs_t is
  record
    div10: integer range 0 to 9;
    rx: rx_regs_t;
    tx: tx_regs_t;
  end record;

  signal r, rin: regs_t;

  -- ILA DEBUG SIGNALS
  -- attribute mark_debug   : string;
  -- attribute keep         : string;
  -- attribute dont_touch   : string;
  -- attribute fsm_encoding : string;

  -- signal rx_regs_ila: rx_regs_t;
  -- attribute dont_touch of rx_regs_ila: signal is "true";
  -- attribute keep       of rx_regs_ila: signal is "user";
  -- attribute mark_debug of rx_regs_ila: signal is "true";
  
  -- signal tx_regs_ila: tx_regs_t;
  -- attribute dont_touch of tx_regs_ila: signal is "true";
  -- attribute keep       of tx_regs_ila: signal is "user";
  -- attribute mark_debug of tx_regs_ila: signal is "true";

  -- signal rx_flit_complete_ila: std_logic;
  -- attribute dont_touch of rx_flit_complete_ila: signal is "true";
  -- attribute keep       of rx_flit_complete_ila: signal is "user";
  -- attribute mark_debug of rx_flit_complete_ila: signal is "true";

  -- signal rx_flit_ila: mii_flit_t;
  -- attribute dont_touch of rx_flit_ila: signal is "true";
  -- attribute keep       of rx_flit_ila: signal is "user";
  -- attribute mark_debug of rx_flit_ila: signal is "true";
  
  -- signal rx_valid_ila: std_logic;
  -- attribute dont_touch of rx_valid_ila: signal is "true";
  -- attribute keep       of rx_valid_ila: signal is "user";
  -- attribute mark_debug of rx_valid_ila: signal is "true";

  -- signal rx_sfd_ila: std_logic;
  -- attribute dont_touch of rx_sfd_ila: signal is "true";
  -- attribute keep       of rx_sfd_ila: signal is "user";
  -- attribute mark_debug of rx_sfd_ila: signal is "true";
  
begin
  -- ILA DEBUG SIGNALS
  -- rx_regs_ila <= r.rx;
  -- tx_regs_ila <= r.tx;
  -- rx_flit_complete_ila <= s_rx_flit_complete;
  -- rx_valid_ila <= rx_valid_s;
  -- rx_sfd_ila <= rx_sfd_s;
  
  -- MII Side
  rx_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rmii_ref_clock_i,
      data_i => reset_n_i,
      data_o => rmii_reset_n_s
      );
  
  regs: process(rmii_ref_clock_i, rmii_reset_n_s) is
  begin
    if rising_edge(rmii_ref_clock_i) then
      r <= rin;
    end if;

    if rmii_reset_n_s = '0' then
      r.rx.state <= RX_INTERFRAME;
      r.rx.dibit_to_go <= "00";
      r.tx.dibit_to_go <= "00";
      r.div10 <= 0;
    end if;
  end process;

  transition: process(r, rmii_i, tx_resynced_flit_s, link_speed_i) is
  begin
    rin <= r;

    if r.div10 /= 0 then
      rin.div10 <= r.div10 - 1;
    else
      if link_speed_i = LINK_SPEED_10 then
        rin.div10 <= 9;
      else
        rin.div10 <= 0;
      end if;
        
      -- RX Side
      rin.rx.is_sfd <= false;
      rin.rx.pipe <= r.rx.pipe(1 to 4) & rmii_i;

      -- One cycle out of 4 makes flit complete
      rin.rx.dibit_to_go <= r.rx.dibit_to_go - 1;

      -- Merge consecutive cycles
      rin.rx.flit.data <= r.rx.pipe(3).rx_d & r.rx.pipe(2).rx_d & r.rx.pipe(1).rx_d & r.rx.pipe(0).rx_d;
      -- Carrier sensing is on first dibit of each nibble.  Validity is
      -- on second dibit of each nibble.  During preamble and SFD, we do
      -- not care to differentiate as CRS_DV is constant high.
      rin.rx.flit.valid <= r.rx.pipe(1).crs_dv and r.rx.pipe(3).crs_dv;
      rin.rx.flit.error <= r.rx.pipe(0).rx_er or r.rx.pipe(1).rx_er or r.rx.pipe(2).rx_er or r.rx.pipe(3).rx_er;

      case r.rx.state is
        when RX_INTERFRAME =>
          if r.rx.pipe(0).crs_dv = '1' and r.rx.pipe(1).crs_dv = '1' then
            rin.rx.state <= RX_PREAMBLE;
          end if;

        when RX_PREAMBLE =>
          if r.rx.flit.data = x"d5" and r.rx.flit.valid = '1' and r.rx.flit.error = '0' then
            rin.rx.is_sfd <= true;
            rin.rx.state <= RX_FRAME;
            rin.rx.dibit_to_go <= "11";
          end if;

        when RX_FRAME =>
          null;
      end case;

      -- Packet end matching, both for PREAMBLE and FRAME states.
      if r.rx.dibit_to_go = 0 and r.rx.pipe(1).crs_dv = '0' and r.rx.pipe(3).crs_dv = '0' then
        rin.rx.state <= RX_INTERFRAME;
      end if;

      -- Tx side
      rin.tx.is_sfd <= false;

      if tx_resynced_flit_s.valid = '0' then
        rin.tx.new_frame <= true;
      elsif r.tx.new_frame and tx_resynced_flit_s.data = x"d5" then
        rin.tx.new_frame <= false;
        rin.tx.is_sfd <= true;
      end if;
      
      rin.tx.dibit_to_go <= r.tx.dibit_to_go - 1;
      rin.tx.flit.data(5 downto 0) <= r.tx.flit.data(7 downto 2);
      if r.tx.dibit_to_go = 0 then
        rin.tx.flit <= tx_resynced_flit_s;
      end if;
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
      reset_n_i => rmii_reset_n_s,
      clock_i(0) => rmii_ref_clock_i,
      clock_i(1) => clock_i,

      out_data_o(7 downto 0) => rx_flit_s.data,
      out_data_o(8) => rx_flit_s.valid,
      out_data_o(9) => rx_flit_s.error,
      out_ready_i => '1',
      out_valid_o => rx_valid_s,

      in_data_i(7 downto 0) => r.rx.flit.data,
      in_data_i(8) => r.rx.flit.valid,
      in_data_i(9) => r.rx.flit.error,
      in_valid_i => s_rx_flit_complete
      );

  s_rx_flit_complete <= to_logic((r.rx.dibit_to_go = 0 and r.div10 = 0)
                                 or (r.rx.state = RX_PREAMBLE
                                     and r.rx.flit.data = x"d5"
                                     and r.rx.flit.valid = '1'
                                     and r.rx.flit.error = '0'
                                     and r.div10 = 0)); -- Always push the SFD,
                                                        -- no matter where in
                                                        -- the flit we are

  rx_to_axi: work.flit.mii_flit_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => rx_flit_s,
      valid_i => rx_valid_s,

      out_o => rx_o,
      out_i => rx_i
      );
  
  -- TX side
  tx_from_axi: work.flit.mii_flit_from_axi4_stream
    generic map(
      ipg_c => ipg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => tx_i,
      in_o => tx_o,

      flit_o => tx_flit_s,
      ready_i => tx_flit_pop_s
      );

  rmii_outputs: process(rmii_ref_clock_i) is
  begin
    if falling_edge(rmii_ref_clock_i) then
      rmii_o.tx_d <= r.tx.flit.data(1 downto 0);
      rmii_o.tx_en <= r.tx.flit.valid;
    end if;
  end process;

  tx_cross_domain: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 10,
      word_count_c => resync_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      clock_i(1) => rmii_ref_clock_i,

      in_data_i(7 downto 0) => tx_flit_s.data,
      in_data_i(8) => tx_flit_s.valid,
      in_data_i(9) => tx_flit_s.error,
      in_valid_i => '1',
      in_ready_o => tx_flit_pop_s,

      out_data_o(7 downto 0) => tx_resynced_flit_s.data,
      out_data_o(8) => tx_resynced_flit_s.valid,
      out_data_o(9) => tx_resynced_flit_s.error,
      out_ready_i => tx_ready_s
      );

  tx_ready_s <= to_logic(r.tx.dibit_to_go = 0 and r.div10 = 0);

  tx_sfd_resync: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => rmii_ref_clock_i,
      input_reset_n_i => rmii_reset_n_s,
      output_clock_i => clock_i,
      tick_i => tx_sfd_s,
      tick_o => tx_sfd_o
      );

  rx_sfd_resync: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => rmii_ref_clock_i,
      input_reset_n_i => rmii_reset_n_s,
      output_clock_i => clock_i,
      tick_i => rx_sfd_s,
      tick_o => rx_sfd_o
      );
  
  rx_sfd_s <= to_logic(r.rx.is_sfd);
  tx_sfd_s <= to_logic(r.tx.is_sfd);
      
end architecture;
