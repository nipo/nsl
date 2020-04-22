library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi;

package transactor is

  constant SPI_CMD_SHIFT_OUT : nsl_bnoc.framed.framed_data_t := "10------";
  constant SPI_CMD_SHIFT_IN  : nsl_bnoc.framed.framed_data_t := "01------";
  constant SPI_CMD_SHIFT_IO  : nsl_bnoc.framed.framed_data_t := "11------";
  constant SPI_CMD_SELECT    : nsl_bnoc.framed.framed_data_t := "000-----";
  constant SPI_CMD_UNSELECT  : nsl_bnoc.framed.framed_data_t := "00011111";
  constant SPI_CMD_DIV       : nsl_bnoc.framed.framed_data_t := "001-----";

  component spi_framed_transactor
    generic(
      slave_count_c : natural range 1 to 31 := 1
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_o  : out std_ulogic;
      cs_n_o : out std_ulogic_vector(0 to slave_count_c-1);
      mosi_o : out std_ulogic;
      miso_i : in  std_ulogic;

      cmd_i : in  nsl_bnoc.framed.framed_req;
      cmd_o : out nsl_bnoc.framed.framed_ack;
      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in  nsl_bnoc.framed.framed_ack
      );
  end component;

end package transactor;
