library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.framed.all;

package spi is

  constant SPI_CMD_SHIFT_OUT : framed_data_t := "10------";
  constant SPI_CMD_SHIFT_IN  : framed_data_t := "01------";
  constant SPI_CMD_SHIFT_IO  : framed_data_t := "11------";
  constant SPI_CMD_SELECT    : framed_data_t := "000-----";
  constant SPI_CMD_UNSELECT  : framed_data_t := "00011111";
  constant SPI_CMD_DIV       : framed_data_t := "001-----";

  constant SPI_FRAMED_GW_STATUS      : framed_data_t := "0-------";
  constant SPI_FRAMED_GW_ST_OUT_RDY  : framed_data_t := "------1-";
  constant SPI_FRAMED_GW_ST_IN_VALID : framed_data_t := "-------1";
  constant SPI_FRAMED_GW_PUT         : framed_data_t := "10------";
  constant SPI_FRAMED_GW_GET         : framed_data_t := "11-----0";
  constant SPI_FRAMED_GW_GET_CONT    : framed_data_t := "11-----1";

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

      p_io_clk        : out std_ulogic;
      p_tx_data       : in  std_ulogic_vector(width - 1 downto 0);
      p_tx_data_get   : out std_ulogic;
      p_rx_data       : out std_ulogic_vector(width - 1 downto 0);
      p_rx_data_valid : out std_ulogic
      );
  end component;

  component spi_framed_gateway
    generic(
      msb_first   : boolean := true
      );
    port(
      p_framed_clk       : in  std_ulogic;
      p_framed_resetn    : in  std_ulogic;

      p_sck       : in  std_ulogic;
      p_csn       : in  std_ulogic;
      p_miso      : out std_ulogic;
      p_mosi      : in  std_ulogic;

      p_out_val   : out framed_req;
      p_out_ack   : in  framed_ack;
      p_in_val    : in  framed_req;
      p_in_ack    : out framed_ack
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

end package spi;
