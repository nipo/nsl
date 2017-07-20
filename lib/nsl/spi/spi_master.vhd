library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;

entity spi_master is
    generic(
      width : natural;
      msb_first : boolean := true
      );
    port(
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_sck    : out std_ulogic;
      p_sck_en : out std_ulogic;
      p_mosi   : out std_ulogic;
      p_miso   : in  std_ulogic;
      p_csn    : out std_ulogic;

      p_run : in std_ulogic;
      
      p_miso_data    : out std_ulogic_vector(width-1 downto 0);
      p_miso_full_n  : in  std_ulogic;
      p_miso_write   : out std_ulogic;

      p_mosi_data    : in  std_ulogic_vector(width-1 downto 0);
      p_mosi_empty_n : in  std_ulogic;
      p_mosi_read    : out std_ulogic
      );
end entity;

architecture rtl of spi_master is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT,
    ST_RUN
    );
  
  type regs_t is record
    state : state_t;
  end record;

  signal r, rin: regs_t;

  signal s_spi_csn, s_spi_clk_en, s_rx_data_valid: std_ulogic;
    
begin

  shreg: spi_shift_register
    generic map(
      width => width,
      msb_first => msb_first
      )
    port map(
      p_spi_clk => p_clk,
      p_spi_word_en => s_spi_clk_en,
      p_spi_dout => p_mosi,
      p_spi_din => p_miso,
      p_tx_data => p_mosi_data,
      p_tx_data_get => p_mosi_read,
      p_rx_data => p_miso_data,
      p_rx_data_valid => s_rx_data_valid
      );

  p_miso_write <= s_rx_data_valid;
  p_csn <= s_spi_csn;
  p_sck_en <= not s_spi_clk_en;
  
  regs: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_run, s_rx_data_valid, p_miso_full_n, p_mosi_empty_n)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if p_run = '1' then
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if p_mosi_empty_n = '1' and p_miso_full_n = '1' then
          rin.state <= ST_RUN;
        end if;

      when ST_RUN =>
        if s_rx_data_valid = '1' then
          if p_run = '0' then
            rin.state <= ST_IDLE;
          elsif p_mosi_empty_n = '1' and p_miso_full_n = '1' then
            rin.state <= ST_RUN;
          else
            rin.state <= ST_WAIT;
          end if;
        end if;
    end case;
  end process;

  moore: process(r, p_clk)
  begin
    case r.state is
      when ST_RESET =>
        s_spi_clk_en <= '0';
        s_spi_csn <= '1';

      when ST_IDLE | ST_WAIT =>
        s_spi_clk_en <= '0';
        s_spi_csn <= '0';

      when ST_RUN =>
        s_spi_clk_en <= '1';
        s_spi_csn <= '0';
    end case;
  end process;
  
end architecture;
