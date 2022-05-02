library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_io;

package sspi is

  -- This component resets target FPGA and loads bitstream as soon as there is
  -- at least one word available on the bitstream input. Bitstream should be
  -- transferred as one frame.
  component sspi_loader is
    generic(
      clock_i_hz_c : natural;
      slave_no_c : natural range 0 to 6;
      -- If set, init_b is assumed to be not connected, and we'll just wait for
      -- fixed timeouts.
      init_b_ignore_c : boolean := false;

      -- SPI Master clock may not be the same as this block's, if a
      -- non-zero value is set here, it is used instead of clock_i_hz_c
      -- for SPI master divisor calculation.
      spi_master_clock_i_hz_c: natural := 0;
      
      -- Refer to datasheets
      -- Configuration SPI clock rate
      cclk_rate_c : natural := 70e6;
      -- Min time to assert program_b for
      tprogram_c: time := 250 ns;
      -- Min time to wait after deasserting program_b for init_b to deassert
      tpl_c: time := 5 ms;
      -- Time to wait after init_b deasserts before config
      ticck_c: time := 150 ns;
      -- Time to wait in the worst case after bitstream is fully sent
      config_timeout_c : time := 5 ms
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      bitstream_i : in nsl_bnoc.framed.framed_req;
      bitstream_o : out nsl_bnoc.framed.framed_ack;

      done_i : in std_ulogic;
      init_b_i : in std_ulogic := '1';
      program_b_o : out nsl_io.io.opendrain;
      
      -- Framed interface to a SPI controller
      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in  nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package sspi;
