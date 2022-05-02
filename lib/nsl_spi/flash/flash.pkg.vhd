library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

package flash is

  component flash_reader is
    generic(
      clock_i_hz_c : natural;
      slave_no_c : natural range 0 to 6;

      -- SPI Master clock may not be the same as this block's, if a
      -- non-zero value is set here, it is used instead of clock_i_hz_c
      -- for SPI master divisor calculation.
      spi_master_clock_i_hz_c: natural := 0;
      
      read_rate_c : natural := 100e6;
      address_byte_count_c: natural := 3;

      read_command_c: byte := x"0b";
      read_dummy_byte_count_c: natural := 1
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      -- Base address value
      address_i : in unsigned(8 * address_byte_count_c - 1 downto 0);
      -- Frame read length minus 1, unbounded
      length_m1_i : in unsigned;
      start_i : in std_ulogic;
      ready_o : out std_ulogic;

      -- Output stream
      data_o : out framed_req;
      data_i : in framed_ack;

      -- Framed interface to a SPI controller
      cmd_o : out framed_req;
      cmd_i : in  framed_ack;
      rsp_i : in  framed_req;
      rsp_o : out framed_ack
      );
  end component;

end package flash;
