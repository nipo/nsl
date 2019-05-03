library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;

entity spi_shift_register is
  generic(
    width : natural;
    msb_first : boolean := true
    );
  port(
    p_spi_clk       : in  std_ulogic;
    p_spi_word_en   : in  std_ulogic;
    p_spi_dout      : out std_ulogic;
    p_spi_din       : in  std_ulogic;

    p_io_clk        : out std_ulogic;
    p_tx_data       : in  std_ulogic_vector(width - 1 downto 0);
    p_tx_data_get   : out std_ulogic;
    p_rx_data       : out std_ulogic_vector(width - 1 downto 0);
    p_rx_data_valid : out std_ulogic
    );
end entity;

architecture rtl of spi_shift_register is

  type regs_t is record
    bit_idx     : natural range 0 to width - 1;
    shreg       : std_ulogic_vector(width - 1 downto 0);
  end record;

  signal r, rin: regs_t;

  function shreg_mosi(shreg : in std_ulogic_vector) return std_ulogic is
  begin
    if msb_first then
      return shreg(shreg'left);
    else
      return shreg(shreg'right);
    end if;
  end function;

  function shreg_shift(shreg : in std_ulogic_vector; miso : std_ulogic) return std_ulogic_vector is
  begin
    if msb_first then
      return shreg(shreg'left-1 downto 0) & miso;
    else
      return miso & shreg(shreg'left downto 1);
    end if;
  end function;

  signal s_io_clk : std_ulogic;

begin

  s_io_clk <= p_spi_clk or not p_spi_word_en;
  p_io_clk <= s_io_clk;

  regs: process(p_spi_clk, p_spi_word_en)
  begin
    if p_spi_word_en = '0' then
      r.bit_idx <= 0;
      r.shreg <= (others => '-');
    elsif falling_edge(p_spi_clk) then
      r <= rin;
    end if;
  end process;

  spi_io: process(r, p_spi_word_en, p_tx_data, p_spi_din)
  begin
    p_tx_data_get <= '0';
    p_rx_data_valid <= '0';
    p_rx_data <= (others => '-');
    p_spi_dout <= shreg_mosi(r.shreg);

    if r.bit_idx = 0 then
      p_spi_dout <= shreg_mosi(p_tx_data);
      p_tx_data_get <= p_spi_word_en;
    end if;

    if r.bit_idx = width - 1 then
      p_rx_data_valid <= p_spi_word_en;
      p_rx_data <= shreg_shift(r.shreg, p_spi_din);
    end if;

  end process;
  
  transition: process(p_spi_din, p_spi_word_en, p_tx_data, r)
  begin
    rin <= r;

    if r.bit_idx = 0 then
      rin.shreg <= shreg_shift(p_tx_data, p_spi_din);
    else
      rin.shreg <= shreg_shift(r.shreg, p_spi_din);
    end if;

    if r.bit_idx = width - 1 then
      rin.bit_idx <= 0;
    else
      rin.bit_idx <= r.bit_idx + 1;
    end if;
  end process;


end architecture;
