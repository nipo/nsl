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

  constant cpol_c: std_ulogic := '1';
  constant cpha_c: std_ulogic := '0';
  constant half_cycle: time := 77 ns;
  
  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  signal addr_s: unsigned(15 downto 0);
  signal tx_data_s, rx_data_s: byte_string(0 to 3);
  signal tx_ready_s, rx_valid_s: std_ulogic;
  signal active_s : std_ulogic;

  signal spi_m: nsl_spi.spi.spi_slave_i;
  signal spi_s: nsl_spi.spi.spi_slave_o;

  procedure spi_io(signal m: out nsl_spi.spi.spi_slave_i;
                   signal s: in nsl_spi.spi.spi_slave_o;
                   tx, rx: byte_string;
                   cpol, cpha : std_ulogic)
  is
    alias txs : byte_string(0 to tx'length-1) is tx;
    alias rxs : byte_string(0 to rx'length-1) is rx;
    variable shreg: std_ulogic_vector(7 downto 0);
  begin
    assert_equal("I/o vectors", tx'length, rx'length, failure);

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

  procedure parallel_tx(signal data: out byte_string;
                        signal ready: in std_ulogic;
                        signal active: in std_ulogic;
                        signal address: in unsigned;
                        addr: unsigned;
                        tx: byte_string)
  is
    alias txs : byte_string(0 to tx'length-1) is tx;
    alias datas : byte_string(0 to data'length-1) is data;
    variable i : integer;
    variable expected_addr : unsigned(addr'range) := addr;
  begin
    datas <= txs(0 to datas'length-1);

    wait until active = '1';

    i := 0;

    while i < txs'length
    loop
      data <= tx(i to i + datas'length - 1);
      if ready = '0' then
        wait until ready = '1';
        assert_equal("Parallel TX addr", address, expected_addr, warning);
      end if;
      wait until ready = '0';

      expected_addr := expected_addr + 1;

      i := i + datas'length;
    end loop;

    data <= (others => dontcare_byte_c);
    wait until active = '0';
  end procedure;

  procedure parallel_rx(signal data: in byte_string;
                        signal valid: in std_ulogic;
                        signal active: in std_ulogic;
                        signal address: in unsigned;
                        addr: unsigned;
                        rx: byte_string)
  is
    alias rxs : byte_string(0 to rx'length-1) is rx;
    alias datas : byte_string(0 to data'length-1) is data;
    variable i : integer;
    variable expected_addr : unsigned(addr'range) := addr;
  begin
    wait until active = '1';

    i := 0;

    while i < rxs'length
    loop
      wait until valid = '1';
      assert_equal("Parallel RX addr", address, expected_addr, warning);
      assert_equal("Parallel RX", datas, rxs(i to i + datas'length - 1), warning);
      wait until valid = '0';

      expected_addr := expected_addr + 1;

      i := i + datas'length;
    end loop;

    wait until active = '0';
  end procedure;
  
begin

  spi_trx: process
  begin
    spi_m.cs_n <= '1';
    done_s(0) <= '0';

    spi_io(spi_m, spi_s, from_hex("031234----------------"), from_hex("------deadbeefdecafbad"), cpol_c, cpha_c);
    spi_io(spi_m, spi_s, from_hex("0b45679876543219876541"), from_hex("----------------------"), cpol_c, cpha_c);

    done_s(0) <= '1';
    wait;
  end process;

  par_trx: process
  begin
    done_s(1) <= '0';

    parallel_tx(tx_data_s, tx_ready_s, active_s, addr_s, x"1234", from_hex("deadbeefdecafbad"));
    parallel_rx(rx_data_s, rx_valid_s, active_s, addr_s, x"4567", from_hex("9876543219876541"));

    done_s(1) <= '1';
    wait;
  end process;
  
  dut: nsl_spi.slave.spi_memory_controller
    generic map(
      addr_bytes_c => addr_s'length/8,
      data_bytes_c => tx_data_s'length,
      write_opcode_c => x"0b"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_i => spi_m,
      spi_o => spi_s,

      selected_o => active_s,

      addr_o => addr_s,

      cpol_i => cpol_c,
      cpha_i => cpha_c,

      rdata_i => tx_data_s,
      rready_o => tx_ready_s,

      wdata_o => rx_data_s,
      wvalid_o => rx_valid_s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );
  
end architecture;
