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
    running     : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(p_spi_clk)
  begin
    if rising_edge(p_spi_clk) then
      r <= rin;
    end if;
  end process;
  
  transition: process (p_spi_word_en, p_spi_clk, r, p_spi_din, p_tx_data)
  begin
    rin <= r;

    if r.running = '0' then
      rin.running <= p_spi_word_en;
      rin.cycle <= width - 1;
    else
      if r.cycle = width - 1 then
        rin.shreg <= p_tx_data;
      elsif msb_first then
        rin.shreg <= r.shreg(width-2 downto 0) & p_spi_din;
      else
        rin.shreg <= p_spi_din & r.shreg(width-1 downto 1);
      end if;
      rin.cycle <= r.cycle - 1;
      if r.cycle = 0 then
        rin.running <= p_spi_word_en;
        rin.cycle <= width - 1;
      end if;
    end if;
  end process;

  moore: process(p_spi_clk)
  begin
    if falling_edge(p_spi_clk) then
      if r.running = '1' then
        if r.cycle = 0 then
          p_rx_data_valid <= '1';
        else
          p_rx_data_valid <= '0';
        end if;

        if r.cycle = width-1 then
          p_tx_data_get <= '1';
        else
          p_tx_data_get <= '0';
        end if;
      else
        p_tx_data_get   <= '0';
        p_rx_data_valid <= '0';
      end if;
    end if;
  end process;

  dout: process(r, rin)
  begin
    p_spi_dout      <= 'Z';
    if r.running = '1' then
      if msb_first then
        p_spi_dout <= rin.shreg(width-1);
      else
        p_spi_dout <= rin.shreg(0);
      end if;
    end if;
  end process;

  p_rx_data <= rin.shreg;

end architecture;
