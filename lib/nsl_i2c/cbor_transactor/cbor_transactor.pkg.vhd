library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_amba, nsl_data;

-- I2C bus master transactor that takes as command stream a pair of AXI Stream pipes.
package cbor_transactor is
    
    -- Responds to CBOR-encoded commands that follow to this specification (CDDL describing valid commands)

    --  A command stream is an array of commands
    --  commands = [* command]
    --  A command can be one of the I2C/I3C operations
    --  command = i2c-write
             -- / i2c-read
             -- / i2c-stop
             -- / i2c-poll-read
    --  i2c-write             = [saddr, bstr]      ; Write bytes
    --  i2c-read              = [saddr, uint]      ; Read count of bytes
    --  i2c-stop              = null
    --  i2c-poll-read         = #6.1([timeout, saddr, uint])
    
    --  Argument definitions
    --  saddr = 0..0x3ff
    --  timeout = 0..1000000 ; microseconds

    --  responses are also in a CBOR-encoded stream
    --  responses = [* response]
    --  response = i2c-ok
             -- / i2c-data
             -- / i2c-addr-nack
             -- / i2c-data-nack
    --  i2c-ok = null
    --  i2c-data = bstr
    --  i2c-addr-nack = false
    --  i2c-data-nack = #6.2(uint) ; nack byte index

  component controller
    generic(
      clock_i_hz_c    : natural;
      target_scl_hz_c : natural := 400000;
      axi_s_cfg_c     : nsl_amba.axi4_stream.config_t
    );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      i2c_o     : out nsl_i2c.i2c.i2c_o;
      i2c_i     : in  nsl_i2c.i2c.i2c_i;
      
      cmd_i     : in nsl_amba.axi4_stream.master_t;
      cmd_o     : out nsl_amba.axi4_stream.slave_t;
      rsp_o     : out nsl_amba.axi4_stream.master_t;
      rsp_i     : in nsl_amba.axi4_stream.slave_t
    );
  end component;

end package cbor_transactor;
