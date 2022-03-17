library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_memory, nsl_logic, nsl_bnoc, nsl_clocking;
use nsl_logic.bool.all;
use nsl_mii.mii.all;
use nsl_mii.rgmii.all;
use nsl_logic.bool.all;

entity rgmii_driver is
  generic(
    rx_clock_delay_ps_c: natural := 0;
    tx_clock_delay_ps_c: natural := 0;
    inband_status_c : boolean := true;
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rgmii_o : out rgmii_io_group_t;
    rgmii_i : in  rgmii_io_group_t;

    mode_o : out rgmii_mode_t;
    link_up_o : out std_ulogic;
    full_duplex_o : out std_ulogic;
    
    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in nsl_bnoc.committed.committed_ack;

    tx_i : in nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of rgmii_driver is

  signal rx_flit_s, tx_flit_s: mii_flit_t;
  signal rx_sdr_s, tx_sdr_s: rgmii_sdr_io_t;
  signal rx_valid_s, tx_ready_s, rx_clock_s: std_ulogic;
  signal mode_s: rgmii_mode_t;
  
begin

  -- RX side
  rgmii_rx: work.rgmii.rgmii_rx_driver
    generic map(
      clock_delay_ps_c => rx_clock_delay_ps_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      rx_clock_o => rx_clock_s,

      mode_i => mode_s,
      rgmii_i => rgmii_i,

      flit_o => rx_sdr_s,
      valid_o => rx_valid_s
      );

  rx_flit_s.data <= rx_sdr_s.data;
  rx_flit_s.valid <= rx_sdr_s.dv;
  rx_flit_s.error <= rx_sdr_s.er;
  
  inband_status: if inband_status_c
  generate
    status_latch: process(clock_i) is
    begin
      if rising_edge(clock_i) then
        if rx_sdr_s.dv = '0' and rx_sdr_s.er = '0' then
          if rx_valid_s = '1' then
            link_up_o <= rx_sdr_s.data(0);
            mode_s <= to_mode(rx_sdr_s.data(2 downto 1));
            full_duplex_o <= rx_sdr_s.data(3);
          end if;
        end if;
      end if;
    end process;
  end generate;

  clock_extracted_status: if not inband_status_c
  generate
    signal rate_index_s : unsigned(1 downto 0);
  begin
    clock_estimator: nsl_clocking.interdomain.clock_rate_estimator
      generic map(
        clock_hz_c => 125.0e6,
        rate_choice_c => (1.0e6, 2.5e6, 25.0e6, 125.0e6)
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        measured_clock_i => rx_clock_s,
        rate_index_o => rate_index_s
        );

    rate_to_mode: process(rate_index_s) is
    begin
      case rate_index_s is
        when "01" =>
          mode_s <= RGMII_MODE_10;
          link_up_o <= '1';
        when "10" =>
          mode_s <= RGMII_MODE_100;
          link_up_o <= '1';
        when "11" =>
          mode_s <= RGMII_MODE_1000;
          link_up_o <= '1';
        when others =>
          mode_s <= RGMII_MODE_10;
          link_up_o <= '0';
      end case;
      full_duplex_o <= '0';
    end process;
  end generate;

  mode_o <= mode_s;
  
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

      mode_i => mode_s,
      flit_i => tx_sdr_s,
      ready_o => tx_ready_s,

      rgmii_o => rgmii_o
      );
      
end architecture;
