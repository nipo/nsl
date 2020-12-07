library ieee;
use ieee.std_logic_1164.all;

library nsl_spi, nsl_clocking;

entity spi_fifo_transport_slave is
  generic(
    width_c : positive
    );
  port(
    -- SPI interface is totally asynchronous to rest of the system
    spi_i       : in  nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;
    irq_n_o     : out std_ulogic;

    -- Clocks the fifo
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

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
    rxd_valid, txd_valid : std_ulogic;

    sent_rx_ready, sent_tx_valid : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  signal spi_word_in_valid, spi_word_out_ready : std_ulogic;
  signal spi_word_in, spi_word_out : shreg_t;

  signal tx_data : std_ulogic_vector(width_c-1 downto 0);
  signal tx_ready, tx_valid, rx_ready : std_ulogic;

  signal spi_reset_n : std_ulogic;
  signal pending_irq : std_ulogic;
  
begin

  spi_word_out(width_c+1) <= not r.rxd_valid;
  spi_word_out(width_c) <= r.txd_valid;
  spi_word_out(width_c-1 downto 0) <= r.txd;

  shreg: nsl_spi.shift_register.spi_shift_register
    generic map(
      width_c => shreg_t'length,
      msb_first_c => true
      )
    port map(
      spi_i => spi_i,
      spi_o => spi_o,

      tx_data_i => spi_word_out,
      tx_strobe_o => spi_word_out_ready,
      rx_data_o => spi_word_in,
      rx_strobe_o => spi_word_in_valid
      );

  -- Slice one word to spi clock
  system_to_spi_fifo: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => width_c
      )
    port map(
      reset_n_i => spi_reset_n,
      clock_i(0) => clock_i,
      clock_i(1) => spi_i.sck,

      in_data_i => tx_data_i,
      in_valid_i => tx_valid_i,
      in_ready_o => tx_ready_o,

      out_data_o => tx_data,
      out_ready_i => tx_ready,
      out_valid_o => tx_valid
      );

  -- Slice one word to spi clock
  spi_to_system_fifo: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => width_c
      )
    port map(
      reset_n_i => spi_reset_n,
      clock_i(0) => spi_i.sck,
      clock_i(1) => clock_i,

      in_data_i => r.rxd,
      in_valid_i => r.rxd_valid,
      in_ready_o => rx_ready,

      out_data_o => rx_data_o,
      out_ready_i => rx_ready_i,
      out_valid_o => rx_valid_o
      );

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => spi_i.sck,
      data_i => reset_n_i,
      data_o => spi_reset_n
      );
  
  regs: process(spi_reset_n, spi_i.sck)
  begin
    if spi_reset_n = '0' then
      r.txd_valid <= '0';
      r.rxd_valid <= '0';
      r.sent_tx_valid <= '0';
      r.sent_rx_ready <= '0';
      r.txd <= (others => '-');
      r.rxd <= (others => '-');
    elsif rising_edge(spi_i.sck) then
      r <= rin;
    end if;
  end process;

  spi_transition: process(r,
                          tx_valid, tx_data, rx_ready,
                          spi_word_in_valid, spi_word_in,
                          spi_word_out_ready)
    variable peer_ready : std_ulogic;
    variable peer_valid : std_ulogic;
    variable peer_data : std_ulogic_vector(width_c-1 downto 0);
  begin
    rin <= r;

    if spi_word_in_valid = '1' then
      peer_ready := spi_word_in(width_c+1);
      peer_valid := spi_word_in(width_c);
      peer_data := spi_word_in(peer_data'range);

      if peer_ready = '1' and r.txd_valid = '1' and r.sent_tx_valid = '1' then
        rin.txd_valid <= '0';
      end if;
        
      if peer_valid = '1' and r.rxd_valid = '0' and r.sent_rx_ready = '1' then
        rin.rxd_valid <= '1';
        rin.rxd <= peer_data;
      end if;
    end if;

    if spi_word_out_ready = '1' then
      rin.sent_tx_valid <= r.txd_valid;
      rin.sent_rx_ready <= not r.rxd_valid;
    end if;

    if r.txd_valid = '0' and tx_valid = '1' then
      rin.txd <= tx_data;
      rin.txd_valid <= '1';
    end if;

    if r.rxd_valid = '1' and rx_ready = '1' then
      rin.rxd_valid <= '0';
    end if;
  end process;

  irq: process(r, spi_i, tx_valid, tx_valid_i)
  begin
    if r.rxd_valid = '1' or tx_valid = '1' or tx_valid_i = '1' or r.txd_valid = '1' then
      pending_irq <= '1';
    elsif rising_edge(spi_i.sck) and spi_i.cs_n = '0' then
      pending_irq <= '0';
    end if;
  end process;

  irq_n_o <= not pending_irq;
  tx_ready <= not r.txd_valid;

end architecture;
