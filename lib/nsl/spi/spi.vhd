library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.framed.all;

package spi is

  constant SPI_CMD_SHIFT_OUT : std_ulogic_vector(7 downto 0) := "10------";
  constant SPI_CMD_SHIFT_IN  : std_ulogic_vector(7 downto 0) := "01------";
  constant SPI_CMD_SHIFT_IO  : std_ulogic_vector(7 downto 0) := "11------";
  constant SPI_CMD_SELECT    : std_ulogic_vector(7 downto 0) := "000-----";
  constant SPI_CMD_UNSELECT  : std_ulogic_vector(7 downto 0) := "00011111";
  constant SPI_CMD_DIV       : std_ulogic_vector(7 downto 0) := "001-----";
  
  component spi_shift_register
    generic(
      width : natural;
      msb_first : boolean := true
      );
    port(
      p_spi_clk       : in  std_ulogic;
      p_spi_word_en   : in  std_ulogic; -- active high, allow shreg operation
      p_spi_dout      : out std_ulogic;
      p_spi_din       : in  std_ulogic;

      p_tx_data       : in  std_ulogic_vector(width - 1 downto 0);
      p_tx_data_get   : out std_ulogic;

      p_rx_data       : out std_ulogic_vector(width - 1 downto 0);
      p_rx_data_valid : out std_ulogic
      );
  end component;

  component spi_master
    generic(
      slave_count : natural range 1 to 63 := 1
      );
    port(
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_sck  : out std_ulogic;
      p_csn  : out std_ulogic_vector(0 to slave_count-1);
      p_mosi : out std_ulogic;
      p_miso : in  std_ulogic;

      p_cmd_val : in  nsl.framed.framed_req;
      p_cmd_ack : out nsl.framed.framed_ack;
      p_rsp_val : out nsl.framed.framed_req;
      p_rsp_ack : in  nsl.framed.framed_ack
      );
  end component;

  component spi_framed_ctrl
    generic(
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

      p_cmd_val   : in nsl.framed.framed_req;
      p_cmd_ack   : out nsl.framed.framed_ack;

      p_rsp_val  : out nsl.framed.framed_req;
      p_rsp_ack  : in nsl.framed.framed_ack
      );
  end component;

end package spi;
