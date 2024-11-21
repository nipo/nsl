library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_io, nsl_data;
use nsl_data.bytestream.all;
use nsl_io.io.all;

entity spi_demux is
  generic(
    sub_address_c : nsl_data.bytestream.byte_string
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    slave_i  : in nsl_spi.spi.spi_slave_i;
    slave_o  : out nsl_spi.spi.spi_slave_o;

    master_o  : out nsl_spi.spi.spi_master_o_vector(0 to sub_address_c'length-1);
    master_i  : in nsl_spi.spi.spi_master_i_vector(0 to sub_address_c'length-1)
    );
end entity;

architecture beh of spi_demux is

  constant slave_count_c : natural := sub_address_c'length;
  constant addresses_c : byte_string(0 to slave_count_c-1) := sub_address_c;
  
  type regs_t is
  record
    selected : boolean;
    target : natural range 0 to slave_count_c - 1;
  end record;

  signal r, rin: regs_t;

  signal rx_data : byte;
  signal rx_strobe, rx_active : std_ulogic;
  signal selector_miso : std_ulogic;
  signal slave_o_muxed_s, slave_o_shreg_s : nsl_spi.spi.spi_slave_o;
  
begin

  shreg: nsl_spi.shift_register.slave_shift_register_oversampled
    generic map(
      width_c => 8,
      msb_first_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => slave_i,
      spi_o => slave_o_shreg_s,

      active_o => rx_active,
      tx_data_i => dontcare_byte_c,
      rx_data_o => rx_data,
      rx_valid_o => rx_strobe
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.selected <= false;
    end if;
  end process regs;

  transition: process(r, rx_data, rx_strobe, rx_active)
  begin
    rin <= r;

    if rx_active = '0' then
      rin.selected <= false;
    elsif rx_strobe = '1' and not r.selected then
      rin.selected <= true;

      for i in addresses_c'range
      loop
        if addresses_c(i) = rx_data then
          rin.target <= i;
        end if;
      end loop;
    end if;
  end process;

  slave_o <= slave_o_muxed_s when r.selected else slave_o_shreg_s;
  
  mealy: process(r, master_i, slave_i)
  begin
    slave_o_muxed_s.miso <= tristated_z;

    for i in addresses_c'range
    loop
      master_o(i).sck <= slave_i.sck;
      master_o(i).cs_n <= opendrain_z;
      master_o(i).mosi <= tristated_z;

      if r.selected and r.target = i then
        slave_o_muxed_s.miso <= to_tristated(master_i(i).miso);
        master_o(i).cs_n.drain_n <= '0';
        master_o(i).mosi <= to_tristated(slave_i.mosi);
      end if;
    end loop;
  end process;
  
end architecture beh;
