library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_simulation, work, nsl_io;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_io.io.all;
use work.spi.all;

package testing is
  
  procedure spi_bitbang(signal m: out work.spi.spi_master_o;
                        signal s: in work.spi.spi_master_i;
                        tx, rx: byte_string;
                        cpol, cpha : std_ulogic;
                        constant half_cycle: time);
  
end package;

package body testing is

  procedure spi_bitbang(signal m: out work.spi.spi_master_o;
                        signal s: in work.spi.spi_master_i;
                        tx, rx: byte_string;
                        cpol, cpha : std_ulogic;
                        constant half_cycle: time)
  is
    alias txs : byte_string(0 to tx'length-1) is tx;
    alias rxs : byte_string(0 to rx'length-1) is rx;
    variable shreg: std_ulogic_vector(7 downto 0);
  begin
    assert_equal("I/o vectors", tx'length, rx'length, failure);

    m.mosi.v <= '-';
    m.mosi.en <= '0';
    m.sck <= cpol;

    wait for half_cycle * 2;
    m.cs_n.drain_n <= '0';
    m.mosi.en <= '1';
    wait for half_cycle;

    for off in txs'range
    loop
      shreg := txs(off);

      for b in shreg'range
      loop
        if cpha = '0' then
          m.mosi.v <= shreg(shreg'left);
          wait for half_cycle;
          m.sck <= not cpol;
          shreg := shreg(shreg'left-1 downto 0) & s.miso;
          wait for half_cycle;
          m.sck <= cpol;
        else
          wait for half_cycle;
          m.sck <= not cpol;
          m.mosi.v <= shreg(shreg'left);
          wait for half_cycle;
          m.sck <= cpol;
          shreg := shreg(shreg'left-1 downto 0) & s.miso;
        end if;
      end loop;

      assert_match("SPI MISO Data at " & to_string(off), shreg, rxs(off), warning);
    end loop;

    wait for half_cycle;
    m.mosi.en <= '0';
    m.cs_n <= opendrain_z;
    wait for half_cycle;
  end procedure;

end package body;
