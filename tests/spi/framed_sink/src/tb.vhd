library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_simulation, nsl_data, nsl_bnoc, nsl_io;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.testing.all;
use nsl_spi.testing.all;
use nsl_spi.spi.all;
use nsl_io.io.all;

entity tb is
end entity;

architecture sim of tb is

  constant cpol_c: std_ulogic := '0';
  constant cpha_c: std_ulogic := '0';
  
  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal spi_master_s: nsl_spi.spi.spi_master_io;
  signal spi_slave_s: nsl_spi.spi.spi_slave_io;
  signal framed_s: nsl_bnoc.framed.framed_bus;

  shared variable from_spi: framed_queue_root;

begin

  spi_master_s.i <= to_master(spi_slave_s.o);
  spi_slave_s.i <= to_slave(spi_master_s.o);

  spi_trx: process
  is
    variable dropped: byte_stream;
  begin
    spi_master_s.o.cs_n <= opendrain_z;
    done_s(0) <= '0';

    spi_bitbang(spi_master_s.o, spi_master_s.i, from_hex("0000010203040506070809"), (0 => "-----0-1", 1 to 10 => "------0-"), cpol_c, cpha_c, 77 ns);
    wait for 1000 ns;
    spi_bitbang(spi_master_s.o, spi_master_s.i, from_hex("00"), (0 => "-000-1--"), cpol_c, cpha_c, 77 ns);
    wait for 3000 ns;
    framed_queue_check("From SPI", from_spi, from_hex("00010203040506070809"));

    spi_bitbang(spi_master_s.o, spi_master_s.i, from_hex("0000010203040506070809"), (0 => "-----0-1", 1 to 9 => "--------", 10 => "------1-"), cpol_c, cpha_c, 35 ns);
    wait for 1000 ns;
    framed_queue_get(from_spi, dropped);

    wait for 10000 ns;
    spi_bitbang(spi_master_s.o, spi_master_s.i, from_hex("0000010203040506070809"), (0 => "-----0-1", 1 to 10 => "------0-"), cpol_c, cpha_c, 77 ns);
    wait for 1000 ns;
    spi_bitbang(spi_master_s.o, spi_master_s.i, from_hex("00"), (0 => "-000-1--"), cpol_c, cpha_c, 77 ns);
    wait for 3000 ns;
    framed_queue_check("From SPI", from_spi, from_hex("00010203040506070809"));

    wait for 3000 ns;
    
    done_s(0) <= '1';
    wait;
  end process;

  popper: process is
    variable data: byte_stream;
  begin
    framed_queue_init(from_spi);

    while true
    loop
      framed_get(framed_s.req, framed_s.ack, clock_s, data, duty_nom => 1, duty_denom => 150);
      log_info("SPI > " & to_string(data.all));
      framed_queue_put(from_spi, data.all);
      deallocate(data);
    end loop;
  end process;

  dut: nsl_spi.slave.spi_framed_sink
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_i => spi_slave_s.i,
      spi_o => spi_slave_s.o,
      cpol_i => cpol_c,
      cpha_i => cpha_c,

      framed_o => framed_s.req,
      framed_i => framed_s.ack
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
