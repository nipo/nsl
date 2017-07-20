library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;

entity spi_shift_register is
  generic(
    width : natural;
    msb_first : boolean := true
    ):
  port(
    p_spi_clk       : in  std_ulogic;
    p_spi_word_en   : in  std_ulogic;
    p_spi_dout      : out std_ulogic;
    p_spi_din       : in  std_ulogic;

    p_tx_data       : in  std_ulogic_vector(width - 1 downto 0);
    p_tx_data_get   : out std_ulogic;

    p_rx_data       : out std_ulogic_vector(width - 1 downto 0);
    p_rx_data_valid : out std_ulogic
    );
end entity;

architecture rtl of spi_shift_register is

  signal r_cycle       : natural range 0 to width - 1;
  signal r_shreg       : std_ulogic_vector(width - 1 downto 0);
  signal s_shreg_next  : std_ulogic_vector(width - 1 downto 0);
  signal s_shreg_shift : std_ulogic_vector(width - 1 downto 0);

begin

  state: process (p_spi_word_en, p_spi_clk)
  begin
    if p_spi_word_en = '0' then
      r_cycle <= 0;
    elsif rising_edge(p_spi_clk) then
      r_shreg <= s_shreg_shift;
      if r_cycle = width - 1 then
        r_cycle <= 0;
      else
        r_cycle <= r_cycle + 1;
      end if;
    elsif falling_edge(p_spi_clk) then
      if msb_first then
        p_spi_dout <= s_shreg_shift(s_shreg_shift'high);
      else
        p_spi_dout <= s_shreg_shift(s_shreg_shift'low);
      end if;
    end if;
  end process;

  s_shreg_next <= p_tx_data when r_cycle = 0 else r_shreg;

  sh: process(s_shreg_next, p_spi_din)
  begin
    if msb_first then
      s_shreg_shift <= s_shreg_next(width - 2 downto 0) & p_spi_din;
    else
      s_shreg_shift <= p_spi_din & s_shreg_next(width - 1 downto 1);
    end if;
  end process;

  p_rx_data_valid <= '1' when r_cycle = width - 1 else '0';
  p_tx_data_get <= '1' when r_cycle = 0 and p_spi_word_en = '1' else '0';
  p_rx_data <= s_shreg_shift;

end architecture;
