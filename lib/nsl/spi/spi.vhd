library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

package spi is

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
      width : natural;
      msb_first : boolean := true
      );
    port(
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_sck    : out std_ulogic;
      p_sck_en : out std_ulogic; -- sck gate, active low, actual sck should be
                                 -- p_sck_en or p_sck
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

      p_cmd_val   : in fifo_framed_cmd;
      p_cmd_ack   : out fifo_framed_rsp;

      p_rsp_val  : out fifo_framed_cmd;
      p_rsp_ack  : in fifo_framed_rsp;
      );
  end component;

end package uart;
