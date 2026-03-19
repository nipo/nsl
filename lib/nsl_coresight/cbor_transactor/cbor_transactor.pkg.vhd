library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_io, nsl_amba, nsl_data;

-- SWD master transactor that takes as command stream a pair of AXI Stream pipes.
package cbor_transactor is

  -- Responds to CBOR-encoded commands that follow this specification (CDDL describing valid commands)
  
  -- A command stream is an array of commands
  -- commands = [* command]

  -- A command can be one of the swd operations
  -- command = swd-run
  --         / swd-turnaround
  --         / swd-bitbang
  --         / swd-rw
  --         / swd-jtag-to-swd

  -- swd-run         = 1..65535   ; Count of cycles to run for
  -- swd-turnaround  = #6.8(1..3) ; Turnaround cycles count. Sticky setting
  -- swd-bitbang     = #6.9(bstr) ; Data stream to send on SWDIO, LE, LSB first
  -- swd-jtag-to-swd = true       ; hardcoded macro

  -- swd-rw   = #6.0(swd-rw-args) ; DP reg0
  --          / #6.1(swd-rw-args) ; DP reg1
  --          / #6.2(swd-rw-args) ; DP reg2
  --          / #6.3(swd-rw-args) ; DP reg3
  --          / #6.4(swd-rw-args) ; AP reg0
  --          / #6.5(swd-rw-args) ; AP reg1
  --          / #6.6(swd-rw-args) ; AP reg2
  --          / #6.7(swd-rw-args) ; AP reg3

  -- swd-rw-args    = swd-read-count / swd-write-data
  -- swd-read-count = uint  ; Number of 32-bit words to read
  -- swd-write-data = bstr  ; 32-bit words to write, little endian. bstr length must be multiple of 4 


  -- The responses are encoded in an array:
  -- responses = [* response]
  -- response = swd-write-response / swd-read-response ; response stream only for reads and writes.
  --                                                   ; If no read or write was performed, an empty array is returned
  
  -- swd-write-response = [offset , swd-status ] 
  -- swd-read-response = [bstr , offset, swd-status]
  
  -- offset = uint ; word index where the failure is, starting at 0. If there are not failures, it will contain the number of read or written words
  -- swd-status = 0..15 ; b0 to b2 is the swd ack response. b3 indicates parity failure.

  -- If there is an error, the command stream will stop being executed from the point where the error happens. The response stream will not have responses for all the commands in the command stream that expect a response (write and read).
  
  component axi4stream_cbor_dp_transactor
    generic(
      clock_i_hz_c    : natural;
      stream_config_c : nsl_amba.axi4_stream.config_t
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      tick_i_hz : in natural;
      tick_i    : in std_ulogic;

      swd_o     : out nsl_coresight.swd.swd_master_o;
      swd_i     : in  nsl_coresight.swd.swd_master_i;

      cmd_i     : in  nsl_amba.axi4_stream.master_t;
      cmd_o     : out nsl_amba.axi4_stream.slave_t;

      rsp_o     : out nsl_amba.axi4_stream.master_t;
      rsp_i     : in  nsl_amba.axi4_stream.slave_t
      );
  end component;

end cbor_transactor;
