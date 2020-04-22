library ieee;
use ieee.std_logic_1164.all;

library nsl_spi;

entity spi_shift_register is
  generic(
    width_c : natural;
    msb_first_c : boolean := true
    );
  port(
    spi_i       : in nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;

    tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
    tx_strobe_o : out std_ulogic;
    rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
    rx_strobe_o : out std_ulogic
    );
end entity;

architecture rtl of spi_shift_register is

  type regs_t is record
    bit_idx     : natural range 0 to width_c - 1;
    shreg       : std_ulogic_vector(width_c - 1 downto 0);
  end record;

  signal r, rin: regs_t;

  function shreg_mosi(shreg : in std_ulogic_vector) return std_ulogic is
  begin
    if msb_first_c then
      return shreg(shreg'left);
    else
      return shreg(shreg'right);
    end if;
  end function;

  function shreg_shift(shreg : in std_ulogic_vector; miso : std_ulogic) return std_ulogic_vector is
  begin
    if msb_first_c then
      return shreg(shreg'left-1 downto 0) & miso;
    else
      return miso & shreg(shreg'left downto 1);
    end if;
  end function;

begin

  regs: process(spi_i.sck, spi_i.cs_n)
  begin
    if spi_i.cs_n = '1' then
      r.bit_idx <= 0;
      r.shreg <= (others => '-');
    elsif rising_edge(spi_i.sck) then
      r <= rin;
    end if;
  end process;

  dout: process(spi_i.sck)
  begin
    if falling_edge(spi_i.sck) then
      spi_o.miso <= shreg_mosi(r.shreg);

      if r.bit_idx = 0 then
        spi_o.miso <= shreg_mosi(tx_data_i);
      end if;
    end if;
  end process;

  spi_io: process(spi_i.mosi, spi_i.cs_n, r)
  begin
    tx_strobe_o <= '0';
    rx_strobe_o <= '0';
    rx_data_o <= (others => '-');

    if r.bit_idx = 0 then
      tx_strobe_o <= not spi_i.cs_n;
    end if;

    if r.bit_idx = width_c - 1 then
      rx_strobe_o <= not spi_i.cs_n;
      rx_data_o <= shreg_shift(r.shreg, spi_i.mosi);
    end if;

  end process;
  
  transition: process(spi_i.mosi, tx_data_i, r)
  begin
    rin <= r;

    if r.bit_idx = 0 then
      rin.shreg <= shreg_shift(tx_data_i, spi_i.mosi);
    else
      rin.shreg <= shreg_shift(r.shreg, spi_i.mosi);
    end if;

    if r.bit_idx = width_c - 1 then
      rin.bit_idx <= 0;
    else
      rin.bit_idx <= r.bit_idx + 1;
    end if;
  end process;


end architecture;
