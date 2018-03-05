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
    cycle       : natural range 0 to width - 1;
    shreg       : std_ulogic_vector(width - 1 downto 0);
  end record;

  signal r, rin: regs_t;

  signal s_io_clk : std_ulogic;

begin

  s_io_clk <= not p_spi_clk and p_spi_word_en;
  p_io_clk <= s_io_clk;
  
  regs: process(p_spi_clk, p_spi_word_en)
  begin
    if p_spi_word_en = '0' then
      r.cycle <= 0;
    elsif rising_edge(p_spi_clk) then
      r <= rin;
    end if;
  end process;

  spi_dout: process(p_spi_clk, p_spi_word_en, p_tx_data)
  begin
    if p_spi_word_en = '0' then
      if msb_first then
        p_spi_dout <= p_tx_data(width-1);
      else
        p_spi_dout <= p_tx_data(0);
      end if;
    elsif falling_edge(p_spi_clk) then
      if msb_first then
        p_spi_dout <= r.shreg(width-1);
      else
        p_spi_dout <= r.shreg(0);
      end if;
    end if;
  end process;
  
  transition: process(p_spi_din, p_spi_word_en, p_tx_data, r)
  begin
    rin <= r;

    if p_spi_word_en = '0' or r.cycle = width-1 then
      rin.shreg <= p_tx_data;
    elsif msb_first then
      rin.shreg <= r.shreg(width-2 downto 0) & p_spi_din;
    else
      rin.shreg <= p_spi_din & r.shreg(width-1 downto 1);
    end if;

    if r.cycle = width - 1 then
      rin.cycle <= 0;
    else
      rin.cycle <= r.cycle + 1;
    end if;
  end process;

  from_spi: process(r, p_spi_din)
  begin
    if msb_first then
      p_rx_data <= r.shreg(width-2 downto 0) & p_spi_din;
    else
      p_rx_data <= p_spi_din & r.shreg(width-1 downto 1);
    end if;
  end process;

  p_tx_data_get <= '1' when p_spi_word_en = '0' or r.cycle = 0 else '0';
  p_rx_data_valid <= '1' when p_spi_word_en = '1' and r.cycle = width - 1 else '0';

end architecture;
