library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling;

package spi is

  constant SPI_CMD_SHIFT_OUT : nsl.framed.framed_data_t := "10------";
  constant SPI_CMD_SHIFT_IN  : nsl.framed.framed_data_t := "01------";
  constant SPI_CMD_SHIFT_IO  : nsl.framed.framed_data_t := "11------";
  constant SPI_CMD_SELECT    : nsl.framed.framed_data_t := "000-----";
  constant SPI_CMD_UNSELECT  : nsl.framed.framed_data_t := "00011111";
  constant SPI_CMD_DIV       : nsl.framed.framed_data_t := "001-----";

  constant SPI_FRAMED_GW_STATUS      : nsl.framed.framed_data_t := "0-------";
  constant SPI_FRAMED_GW_ST_OUT_RDY  : nsl.framed.framed_data_t := "------1-";
  constant SPI_FRAMED_GW_ST_IN_VALID : nsl.framed.framed_data_t := "-------1";
  constant SPI_FRAMED_GW_PUT         : nsl.framed.framed_data_t := "10------";
  constant SPI_FRAMED_GW_GET         : nsl.framed.framed_data_t := "11-----0";
  constant SPI_FRAMED_GW_GET_CONT    : nsl.framed.framed_data_t := "11-----1";

  component spi_shift_register
    generic(
      width : natural;
      msb_first : boolean := true
      );
    port(
      spi_i       : in signalling.spi.spi_slave_i;
      spi_o       : out signalling.spi.spi_slave_o;

      tx_data_i   : in  std_ulogic_vector(width - 1 downto 0);
      tx_strobe_o : out std_ulogic;
      rx_data_o   : out std_ulogic_vector(width - 1 downto 0);
      rx_strobe_o : out std_ulogic
      );
  end component;
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

      p_out_val   : out nsl.framed.framed_req;
      p_out_ack   : in  nsl.framed.framed_ack;
      p_in_val    : in  nsl.framed.framed_req;
      p_in_ack    : out nsl.framed.framed_ack
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
