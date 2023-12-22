library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_bnoc, nsl_spi, nsl_io, nsl_data, nsl_logic;
use nsl_data.bytestream.all;

package transactor is

  constant SPI_CMD_SHIFT_OUT    : nsl_bnoc.framed.framed_data_t := "10------";
  constant SPI_CMD_SHIFT_IN     : nsl_bnoc.framed.framed_data_t := "01------";
  constant SPI_CMD_SHIFT_IO     : nsl_bnoc.framed.framed_data_t := "11------";
  constant SPI_CMD_SELECT       : nsl_bnoc.framed.framed_data_t := "000-----";
  constant SPI_CMD_SELECT_CPOL0 : nsl_bnoc.framed.framed_data_t := "---0----";
  constant SPI_CMD_SELECT_CPOL1 : nsl_bnoc.framed.framed_data_t := "---1----";
  constant SPI_CMD_SELECT_CPHA0 : nsl_bnoc.framed.framed_data_t := "----0---";
  constant SPI_CMD_SELECT_CPHA1 : nsl_bnoc.framed.framed_data_t := "----1---";
  constant SPI_CMD_SELECT_MODE0 : nsl_bnoc.framed.framed_data_t := "---00---";
  constant SPI_CMD_SELECT_MODE1 : nsl_bnoc.framed.framed_data_t := "---01---";
  constant SPI_CMD_SELECT_MODE2 : nsl_bnoc.framed.framed_data_t := "---10---";
  constant SPI_CMD_SELECT_MODE3 : nsl_bnoc.framed.framed_data_t := "---11---";
  constant SPI_CMD_UNSELECT     : nsl_bnoc.framed.framed_data_t := "000--111";
  constant SPI_CMD_DIV          : nsl_bnoc.framed.framed_data_t := "001-----";

  function spi_select(cs: integer := -1;
                      cpol : std_ulogic := '0';
                      cpha : std_ulogic := '0')
    return nsl_data.bytestream.byte_string;

  function spi_select(cs: integer := -1;
                      mode : integer range 0 to 3 := 0)
    return nsl_data.bytestream.byte_string;

  function spi_div(divisor : integer range 1 to 32)
    return nsl_data.bytestream.byte_string;

  function spi_clock(clock_hz: real; sck_hz: real)
    return nsl_data.bytestream.byte_string;

  function spi_shift(byte_count: integer range 1 to 64; read_miso : boolean)
    return nsl_data.bytestream.byte_string;

  function spi_shift(mosi: nsl_data.bytestream.byte_string; read_miso : boolean)
    return nsl_data.bytestream.byte_string;
  
  component spi_framed_transactor
    generic(
      slave_count_c : natural range 1 to 7 := 1
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_o  : out std_ulogic;
      cs_n_o : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
      mosi_o : out std_ulogic;
      miso_i : in  std_ulogic;

      cmd_i : in  nsl_bnoc.framed.framed_req;
      cmd_o : out nsl_bnoc.framed.framed_ack;
      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in  nsl_bnoc.framed.framed_ack
      );
  end component;

  component spi_muxed_transactor
    generic(
      unselected_mask_c : std_ulogic_vector(7 downto 0) := x"ff";
      extender_slave_no_c: integer;
      muxed_slave_no_c: integer
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      slave_cmd_i : in  nsl_bnoc.framed.framed_req;
      slave_cmd_o : out nsl_bnoc.framed.framed_ack;
      slave_rsp_o : out nsl_bnoc.framed.framed_req;
      slave_rsp_i : in  nsl_bnoc.framed.framed_ack;

      master_cmd_i : in  nsl_bnoc.framed.framed_ack;
      master_cmd_o : out nsl_bnoc.framed.framed_req;
      master_rsp_o : out nsl_bnoc.framed.framed_ack;
      master_rsp_i : in  nsl_bnoc.framed.framed_req
      );
  end component;

end package transactor;

package body transactor is

  use nsl_logic.bool.all;
  
  function spi_select(cs: integer := -1;
                      cpol : std_ulogic := '0';
                      cpha : std_ulogic := '0')
    return nsl_data.bytestream.byte_string
  is
    variable ret: nsl_data.bytestream.byte_string(0 to 0);
  begin
    ret(0) := "000" & cpol & cpha & std_ulogic_vector(to_unsigned(cs mod 8, 3));

    return ret;
  end function;

  function spi_select(cs: integer := -1;
                      mode : integer range 0 to 3 := 0)
    return nsl_data.bytestream.byte_string
  is
    constant mode_v : unsigned(1 downto 0) := to_unsigned(mode, 2);
  begin
    return spi_select(cs, mode_v(1), mode_v(0));
  end function;

  function spi_div(divisor : integer range 1 to 32)
    return nsl_data.bytestream.byte_string
  is
    variable ret: nsl_data.bytestream.byte_string(0 to 0);
  begin
    ret(0) := "001" & std_ulogic_vector(to_unsigned(divisor-1, 5));

    return ret;
  end function;

  function spi_clock(clock_hz: real; sck_hz: real)
    return nsl_data.bytestream.byte_string
  is
    constant ratio : real := clock_hz / sck_hz / 2.0;
  begin
    if ratio < 1.0 then
      return spi_div(1);
    elsif ratio > 31.0 then
      return spi_div(32);
    else
      return spi_div(integer(ceil(ratio)));
    end if;
  end function;

  function spi_shift(byte_count: integer range 1 to 64; read_miso : boolean)
    return nsl_data.bytestream.byte_string
  is
    variable ret: nsl_data.bytestream.byte_string(0 to 0);
    constant pad: nsl_data.bytestream.byte_string(1 to byte_count) := (others => "00000000");
  begin
    -- We have no option to have no input/no output shift, so shift zeros
    -- when we have no miso reading.
    if read_miso then
      ret(0) := std_ulogic_vector("01" & to_unsigned(byte_count-1, 6));
      return ret;
    else
      ret(0) := std_ulogic_vector("10" & to_unsigned(byte_count-1, 6));
      return ret & pad;
    end if;
  end function;

  function spi_shift(mosi: nsl_data.bytestream.byte_string; read_miso : boolean)
    return nsl_data.bytestream.byte_string
  is
    variable ret: nsl_data.bytestream.byte_string(0 to 0);
  begin
    assert 0 < mosi'length
      report "Must have MOSI data"
      severity failure;
    assert mosi'length <= 64
      report "MOSI data cannot be more than 64 bytes"
      severity failure;

    ret(0) := "1" & to_logic(read_miso) & std_ulogic_vector(to_unsigned(mosi'length-1, 6));

    return ret & mosi;
  end function;

end package body;
