library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc, nsl_inet, nsl_spi, nsl_line_coding;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_bnoc.testing.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal s_spi_committed, s_spi_committed_relax, s_spi_addressed: nsl_bnoc.committed.committed_bus;
  signal s_spi_slave: nsl_bnoc.pipe.pipe_bus_t;
  signal spi_m: nsl_spi.spi.spi_slave_i;
  signal spi_s: nsl_spi.spi.spi_slave_o;

  constant half_cycle: time := 77 ns;

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
          shreg := shreg(shreg'left-1 downto 0) & s.miso.v;
          wait for half_cycle;
          m.sck <= cpol;
        else
          wait for half_cycle;
          m.sck <= not cpol;
          m.mosi <= shreg(shreg'left);
          wait for half_cycle;
          m.sck <= cpol;
          shreg := shreg(shreg'left-1 downto 0) & s.miso.v;
        end if;
      end loop;

      assert_equal("SPI MISO Data", shreg, rxs(off), warning);
    end loop;

    wait for half_cycle;
    m.cs_n <= '1';
    wait for half_cycle;
  end procedure;

begin

  spi_trx: process
  begin
    spi_m.cs_n <= '1';
    done_s(0) <= '0';

    spi_io(spi_m, spi_s, from_hex("00"), from_hex("03"), '0', '0');
    spi_io(spi_m, spi_s, from_hex("00010203040506"), from_hex("03------------"), '0', '0');

    wait for 50 us;
    
    done_s(0) <= '1';
    wait;
  end process;

  spi_slave: nsl_spi.slave.spi_committed_sink
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_i => spi_m,
      spi_o => spi_s,

      cpol_i => '0',
      cpha_i => '0',

      committed_o => s_spi_committed.req,
      committed_i => s_spi_committed.ack
      );

  spi_committed_fifo: nsl_bnoc.committed.committed_fifo
    generic map(
      depth_c => 1024
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => clock_s,

      in_i => s_spi_committed.req,
      in_o => s_spi_committed.ack,

      out_o => s_spi_committed_relax.req,
      out_i => s_spi_committed_relax.ack
      );
  
  spi_slave_addresser: nsl_bnoc.committed.committed_header_inserter
    generic map(
      header_length_c => 2
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      header_i => (x"00", x"00"),
      capture_i => '1',

      in_i => s_spi_committed_relax.req,
      in_o => s_spi_committed_relax.ack,

      out_o => s_spi_addressed.req,
      out_i => s_spi_addressed.ack
      );
  
  spi_slave_framer: nsl_line_coding.hdlc.hdlc_framer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      frame_i => s_spi_addressed.req,
      frame_o => s_spi_addressed.ack,

      hdlc_o => s_spi_slave.req,
      hdlc_i => s_spi_slave.ack
      );

  s_spi_slave.ack <= nsl_bnoc.pipe.pipe_ack_blackhole_c;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 30 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

  
end;
