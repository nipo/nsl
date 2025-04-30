library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

package source is

  -- This component generates write-only SPI transactions through the attached
  -- SPI transactor. It targets given slave index with defined mode.
  --
  -- ATM, this module is barely capable of putting data to a
  -- spi_committed_sink with no back-pressure or error management.
  component spi_committed_source is
    generic(
      buffer_size_c: integer range 1 to 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      committed_i  : in nsl_bnoc.committed.committed_req;
      committed_o  : out nsl_bnoc.committed.committed_ack;
      
      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';
      slave_i : in unsigned(2 downto 0) := "000";
      div_i : in unsigned(6 downto 0) := "0000000";

      spi_cmd_o  : out nsl_bnoc.framed.framed_req;
      spi_cmd_i  : in nsl_bnoc.framed.framed_ack;

      spi_rsp_i  : in nsl_bnoc.framed.framed_req;
      spi_rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  -- This component generates write-only SPI transactions through the attached
  -- SPI transactor. It targets given slave index with defined mode.
  --
  -- There is no prefix or postfix in data. /CS will be deasserted when no more
  -- byte appears on pipe interface at least timeout_c cycles.
  component spi_pipe_source is
    generic(
      timeout_c : positive;
      buffer_size_c: integer range 1 to 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pipe_i  : in nsl_bnoc.pipe.pipe_req_t;
      pipe_o  : out nsl_bnoc.pipe.pipe_ack_t;
      
      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';
      slave_i : in unsigned(2 downto 0) := "000";
      div_i : in unsigned(6 downto 0) := "0000000";

      spi_cmd_o  : out nsl_bnoc.framed.framed_req_t;
      spi_cmd_i  : in nsl_bnoc.framed.framed_ack_t;

      spi_rsp_i  : in nsl_bnoc.framed.framed_req_t;
      spi_rsp_o  : out nsl_bnoc.framed.framed_ack_t
      );
  end component;

end package source;
