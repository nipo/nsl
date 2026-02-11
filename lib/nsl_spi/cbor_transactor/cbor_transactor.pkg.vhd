library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_amba, nsl_data, nsl_io;

-- SPI master transactor that takes as command stream a pair of AXI Stream pipes.
package cbor_transactor is
  
    -- Responds to CBOR-encoded commands that follow this specification (CDDL describing valid commands)

    -- A command stream is an array of commands 
    -- commands = [* command]

    -- A command can be one of the SPI operations
    -- command = spi-shift
    --         / spi-select
    --         / spi-unselect
    --         / spi-pause        

    -- spi-shift         = spi-shift-bytes
    --                   / spi-shift-short
    --                   / spi-shift-cycles
    -- spi-shift-bytes   = bstr .size (1..4095)
    -- spi-shift-short   = spi-shift-minus1 / spi-shift-minus2 / spi-shift-minus3
    --                    / spi-shift-minus4 / spi-shift-minus5 / spi-shift-minus6
    --                    / spi-shift-minus7

    -- spi-shift-minus1  = #6.1(spi-shift-bytes) ; do not shift the last 1 bits of the argument                  
    -- spi-shift-minus2  = #6.2(spi-shift-bytes) ; do not shift the last 2 bits of the argument                  
    -- spi-shift-minus3  = #6.3(spi-shift-bytes) ; do not shift the last 3 bits of the argument                  
    -- spi-shift-minus4  = #6.4(spi-shift-bytes) ; do not shift the last 4 bits of the argument                  
    -- spi-shift-minus5  = #6.5(spi-shift-bytes) ; do not shift the last 5 bits of the argument
    -- spi-shift-minus6  = #6.6(spi-shift-bytes) ; do not shift the last 6 bits of the argument                  
    -- spi-shift-minus7  = #6.7(spi-shift-bytes) ; do not shift the last 7 bits of the argument                  

    -- spi-shift-cycles  = #6.8(1..65535)  ; returns bstr of (size + 7) / 8
    -- spi-shift-no-miso = #6.9(spi-shift) ; will not return data
    -- spi-pause         = #6.10(uint)     ; wait for x bit time

    -- spi-select        = [cs, mode]
    -- cs                = 0..3
    -- mode              = 0..3
    -- spi-unselect      = null

    -- The responses are encoded in an array:
    -- responses = [* response]
    -- response = spi-shift-bytes    ; response data stream, only for shifts not tagged with #6.9

  component axi4stream_cbor_spi_transactor
    generic(
      clock_i_hz_c  : natural;
      stream_config_c   : nsl_amba.axi4_stream.config_t;
      slave_count_c : natural range 1 to 7 := 1;
      width_c       : natural := 7
    );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i    : in std_ulogic;
            
      sck_o     : out std_ulogic;
      cs_n_o    : out nsl_io.io.opendrain_vector(0 to slave_count_c-1);
      mosi_o    : out nsl_io.io.tristated;
      miso_i    : in  std_ulogic;
      
      cmd_i     : in  nsl_amba.axi4_stream.master_t;
      cmd_o     : out nsl_amba.axi4_stream.slave_t;
      rsp_o     : out nsl_amba.axi4_stream.master_t;
      rsp_i     : in nsl_amba.axi4_stream.slave_t
    );
  end component;

end package cbor_transactor;
