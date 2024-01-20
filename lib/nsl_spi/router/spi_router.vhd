library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_io;

entity spi_router is
  generic(
    slave_count_c : positive range 1 to 255
    );
  port(
    spi_i  : in nsl_spi.spi.spi_slave_i;
    spi_o  : out nsl_spi.spi.spi_slave_o;

    sck_o  : out std_ulogic;
    cs_n_o : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
    mosi_o : out nsl_io.io.tristated;
    miso_i : in  std_ulogic_vector(0 to slave_count_c-1)
    );
end entity;

architecture beh of spi_router is

  type regs_t is
  record
    selected : boolean;
    valid : boolean;
    target : positive range 0 to slave_count_c - 1;
  end record;

  signal r, rin: regs_t;

  signal rx_data : std_ulogic_vector(7 downto 0);
  signal rx_strobe : std_ulogic;
  signal selector_miso : std_ulogic;
  
begin

  shreg: nsl_spi.shift_register.spi_shift_register
    generic map(
      width_c => 8,
      msb_first_c => true
      )
    port map(
      spi_i => spi_i,
      spi_o.miso => selector_miso,

      tx_data_i => x"2a",
      tx_strobe_o => open,
      rx_data_o => rx_data,
      rx_strobe_o => rx_strobe
      );

  regs: process(spi_i.sck, spi_i.cs_n)
  begin
    if rising_edge(spi_i.sck) then
      r <= rin;
    end if;
    if spi_i.cs_n = '1' then
      r.selected <= false;
      r.valid <= false;
    end if;
  end process regs;

  transition: process(r, rx_data, rx_strobe)
  begin
    rin <= r;

    if rx_strobe = '1' and not r.selected then
      rin.selected <= true;
      if to_integer(unsigned(rx_data)) < slave_count_c then
        rin.valid <= true;
        rin.target <= to_integer(unsigned(rx_data));
      end if;
    end if;
  end process;

  mealy: process(miso_i, r, selector_miso)
  begin
    spi_o.miso <= selector_miso;

    if r.selected and r.valid then
      spi_o.miso <= miso_i(r.target);
    end if;
  end process;

  moore: process(spi_i.sck)
  begin
    if falling_edge(spi_i.sck) then
      cs_n_o <= (others => (drain_n => '1'));
      mosi_o.en <= '0';

      if r.selected and r.valid then
        cs_n_o(r.target).drain_n <= '0';
        mosi_o.en <= '1';
      end if;
    end if;
  end process;

  sck_o <= spi_i.sck;
  mosi_o.v <= spi_i.mosi;
  
end architecture beh;
