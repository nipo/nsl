library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_simulation, nsl_data;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;

entity tb is
end entity;

architecture sim of tb is

  signal clock_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

  signal tx_data_s, rx_data_s: std_ulogic_vector(7 downto 0);
  signal tx_ready_s, rx_valid_s: std_ulogic;
  signal active_s : std_ulogic;

  signal spi_m: nsl_spi.spi.spi_slave_i;
  signal spi_s: nsl_spi.spi.spi_slave_o;

  signal cpol_s, cpha_s : std_ulogic;
  
  constant half_cycle: time := 55 ns;
  
  procedure spi_io(signal m: out nsl_spi.spi.spi_slave_i;
                   signal s: in nsl_spi.spi.spi_slave_o;
                   signal spi_cpol_s, spi_cpha_s: out std_ulogic;
                   tx, rx: byte_string;
                   cpol, cpha : std_ulogic)
  is
    alias txs : byte_string(0 to tx'length-1) is tx;
    alias rxs : byte_string(0 to rx'length-1) is rx;
    variable shreg: std_ulogic_vector(7 downto 0);
  begin
    assert_equal("I/o vectors", tx'length, rx'length, failure);

    spi_cpol_s <= cpol;
    spi_cpha_s <= cpha;
    m.mosi <= '-';
    m.sck <= cpol;

    wait for 40 ns;
    wait for half_cycle;
    m.cs_n <= '0';
    wait for half_cycle;

    for off in txs'range
    loop
      shreg := txs(off);

      for b in shreg'range
      loop
        if cpha = '0' then
          m.mosi <= shreg(shreg'left);
          wait for half_cycle;
          m.sck <= not cpol;
          shreg := shreg(shreg'left-1 downto 0) & s.miso;
          wait for half_cycle;
          m.sck <= cpol;
        else
          wait for half_cycle;
          m.sck <= not cpol;
          m.mosi <= shreg(shreg'left);
          wait for half_cycle;
          m.sck <= cpol;
          shreg := shreg(shreg'left-1 downto 0) & s.miso;
        end if;
      end loop;

      assert_equal("SPI MISO Data", shreg, rxs(off), warning);
    end loop;

    wait for half_cycle;
    m.cs_n <= '1';
    wait for half_cycle;
  end procedure;

  procedure parallel_tx(signal data: out std_ulogic_vector(7 downto 0);
                        signal ready: in std_ulogic;
                        signal active: in std_ulogic;
                        tx: byte_string)
  is
  begin
    data <= tx(tx'left);

    wait until active = '1';

    for off in tx'range
    loop
      data <= tx(off);
      if ready = '0' then
        wait until ready = '1';
      end if;
      wait until ready = '0';
    end loop;

    data <= (others => '-');
    wait until active = '0';
  end procedure;

  procedure parallel_rx(signal data: in std_ulogic_vector(7 downto 0);
                        signal valid: in std_ulogic;
                        signal active: in std_ulogic;
                        rx: byte_string)
  is
  begin
    wait until active = '1';

    for off in rx'range
    loop
      wait until valid = '1';
      assert_equal("Parallel RX", data, rx(off), warning);
      wait until valid = '0';
    end loop;

    wait until active = '0';
  end procedure;
  
begin

  spi_trx: process
  begin
    spi_m.cs_n <= '1';
    done_s(0) <= '0';

    spi_io(spi_m, spi_s, cpol_s, cpha_s, from_hex("deadbeef"), from_hex("decafbad"), '0', '0');
    spi_io(spi_m, spi_s, cpol_s, cpha_s, from_hex("deadbeef"), from_hex("decafbad"), '1', '0');
    spi_io(spi_m, spi_s, cpol_s, cpha_s, from_hex("deadbeef"), from_hex("decafbad"), '0', '1');
    spi_io(spi_m, spi_s, cpol_s, cpha_s, from_hex("deadbeef"), from_hex("decafbad"), '1', '1');

    done_s(0) <= '1';
    wait;
  end process;

  par_tx: process
  begin
    done_s(1) <= '0';

    parallel_tx(tx_data_s, tx_ready_s, active_s, from_hex("decafbad"));
    parallel_tx(tx_data_s, tx_ready_s, active_s, from_hex("decafbad"));
    parallel_tx(tx_data_s, tx_ready_s, active_s, from_hex("decafbad"));
    parallel_tx(tx_data_s, tx_ready_s, active_s, from_hex("decafbad"));

    done_s(1) <= '1';
    wait;
  end process;

  par_rx: process
  begin
    done_s(2) <= '0';

    parallel_rx(rx_data_s, rx_valid_s, active_s, from_hex("deadbeef"));
    parallel_rx(rx_data_s, rx_valid_s, active_s, from_hex("deadbeef"));
    parallel_rx(rx_data_s, rx_valid_s, active_s, from_hex("deadbeef"));
    parallel_rx(rx_data_s, rx_valid_s, active_s, from_hex("deadbeef"));

    done_s(2) <= '1';
    wait;
  end process;
  
  dut: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => 8
      )
    port map(
      clock_i => clock_s,

      cpol_i => cpol_s,
      cpha_i => cpha_s,

      spi_i => spi_m,
      spi_o => spi_s,

      active_o => active_s,
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_data_o => rx_data_s,
      rx_valid_o => rx_valid_s
      );
      
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 0,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      done_i => done_s
      );
  
end architecture;
