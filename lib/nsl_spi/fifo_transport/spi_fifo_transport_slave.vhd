library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_clocking;

entity spi_fifo_transport_slave is
  generic(
    width_c : positive;
    cs_n_active_c : std_ulogic := '0'
    );
  port(
    -- Clocks the fifo and the SPI slave
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    spi_i       : in  nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;
    irq_n_o     : out std_ulogic;

    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';


    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_valid_i  : in  std_ulogic;
    tx_ready_o  : out std_ulogic;

    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_valid_o  : out std_ulogic;
    rx_ready_i  : in  std_ulogic
    );
end entity;

architecture beh of spi_fifo_transport_slave is

  subtype shreg_t is std_ulogic_vector(width_c+2-1 downto 0);
  -- Ready, Valid, Data[width_c]

  type regs_t is
  record
    rxd, txd : std_ulogic_vector(width_c-1 downto 0);
    rxd_valid, txd_valid, running : std_ulogic;

    sent_rx_ready, sent_tx_valid : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  signal tx_data_s, rx_data_s : shreg_t;
  signal tx_ready_s, rx_valid_s, active_s : std_ulogic;
  
begin

  tx_data_s(width_c+1) <= not r.rxd_valid and r.running;
  tx_data_s(width_c) <= r.txd_valid and r.running;
  tx_data_s(width_c-1 downto 0) <= r.txd;

  shreg: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => shreg_t'length,
      msb_first_c => true,
      cs_n_active_c => cs_n_active_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => spi_i,
      spi_o => spi_o,

      cpol_i => cpol_i,
      cpha_i => cpha_i,

      active_o => active_s,
      
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_data_o => rx_data_s,
      rx_valid_o => rx_valid_s
      );
  
  
  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    
    if reset_n_i = '0' then
      r.txd <= (others => '0');
      r.running <= '0';
      r.txd_valid <= '0';
      r.rxd_valid <= '0';
      r.sent_tx_valid <= '0';
      r.sent_rx_ready <= '0';
    end if;
  end process;

  spi_transition: process(r, tx_ready_s, rx_valid_s,
                          rx_data_s, active_s,
                          tx_data_i, tx_valid_i, rx_ready_i) is
    variable peer_ready : std_ulogic;
    variable peer_valid : std_ulogic;
    variable peer_data : std_ulogic_vector(width_c-1 downto 0);
  begin
    rin <= r;

    if active_s = '0' then
      rin.running <= '1';
    end if;

    peer_ready := rx_data_s(width_c+1);
    peer_valid := rx_data_s(width_c);
    peer_data := rx_data_s(peer_data'range);

    if r.running = '1' then
      if rx_valid_s = '1' then
        if peer_ready = '1' and r.txd_valid = '1' and r.sent_tx_valid = '1' then
          rin.txd_valid <= '0';
          rin.txd <= (others => '0');
        end if;
        
        if peer_valid = '1' and r.rxd_valid = '0' and r.sent_rx_ready = '1' then
          rin.rxd_valid <= '1';
          rin.rxd <= peer_data;
        end if;
      end if;

      if tx_ready_s = '1' then
        rin.sent_tx_valid <= r.txd_valid;
        rin.sent_rx_ready <= not r.rxd_valid;
      end if;

      if r.txd_valid = '0' and tx_valid_i = '1' then
        rin.txd <= tx_data_i;
        rin.txd_valid <= '1';
      end if;

      if r.rxd_valid = '1' and rx_ready_i = '1' then
        rin.rxd_valid <= '0';
      end if;
    end if;
  end process;

  rx_data_o <= r.rxd;
  rx_valid_o <= r.rxd_valid and r.running;
  tx_ready_o <= not r.txd_valid and r.running;
  irq_n_o <= not tx_valid_i;

end architecture;
