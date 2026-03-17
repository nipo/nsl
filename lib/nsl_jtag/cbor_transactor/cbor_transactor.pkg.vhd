library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_io, nsl_amba, nsl_data;

-- JTAG ATE transactor that takes as command stream a pair of AXI Stream pipes.
package cbor_transactor is

    -- Responds to CBOR-encoded commands that follow this specification (CDDL describing valid commands)

    -- A command stream is an array of commands
    -- commands = [* command]
    

    -- A command can be one of the jtag operations
    -- command =
    --       jtag-shift
    --     / jtag-shift-no-tdo
    --     / jtag-dr-capture
    --     / jtag-ir-capture
    --     / jtag-swd-to-jtag
    --     / jtag-reset
    --     / jtag-run
    --     / jtag-run-time

    -- jtag-shift        = jtag-shift-bytes / jtag-shift-short / jtag-shift-cycles
    -- jtag-shift-bytes  = bstr .size (1..4095)
    -- jtag-shift-short  = jtag-shift-minus1 / jtag-shift-minus2 / jtag-shift-minus3
    --                   / jtag-shift-minus4 / jtag-shift-minus5 / jtag-shift-minus6
    --                   / jtag-shift-minus7

    -- jtag-shift-minus1 = #6.1(jtag-shift-bytes) ; do not shift the last 1 bits of the argument                  
    -- jtag-shift-minus2 = #6.2(jtag-shift-bytes) ; do not shift the last 2 bits of the argument                  
    -- jtag-shift-minus3 = #6.3(jtag-shift-bytes) ; do not shift the last 3 bits of the argument                  
    -- jtag-shift-minus4 = #6.4(jtag-shift-bytes) ; do not shift the last 4 bits of the argument                  
    -- jtag-shift-minus5 = #6.5(jtag-shift-bytes) ; do not shift the last 5 bits of the argument
    -- jtag-shift-minus6 = #6.6(jtag-shift-bytes) ; do not shift the last 6 bits of the argument                  
    -- jtag-shift-minus7 = #6.7(jtag-shift-bytes) ; do not shift the last 7 bits of the argument                  

    -- jtag-shift-cycles = #6.8( 1..65535 )  ; returns bstr of (size + 7) / 8
    -- jtag-shift-no-tdo = #6.9(jtag-shift)  ; will not return data

    -- jtag-dr-capture   = #7.1
    -- jtag-ir-capture   = #7.2
    -- jtag-swd-to-jtag  = #7.3          ; hardcoded macro
    -- jtag-reset        = #6.10(uint)   ; min number of cycles in RTI
    -- jtag-run          = uint          ; min number of run cycles (can be 0, implies update if shifting)
    -- jtag-run-time     = #6.11(uint)   ; min number of ms to run for

    -- Possible responses
    -- responses = [* response]

    -- response = jtag-shift-bytes    ; response data stream, only for shifts not tagged with #6.9

  component controller
    generic(
      clock_i_hz_c : natural;
      axi_s_cfg_c  : nsl_amba.axi4_stream.config_t
    );
    port (
      clock_i      : in  std_ulogic;
      reset_n_i    : in  std_ulogic;

      tick_i_hz    : in natural;
      tick_i       : in  std_ulogic;

      cmd_i        : in  nsl_amba.axi4_stream.master_t;
      cmd_o        : out nsl_amba.axi4_stream.slave_t;
      rsp_o        : out nsl_amba.axi4_stream.master_t;
      rsp_i        : in  nsl_amba.axi4_stream.slave_t;

      jtag_o       : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i       : in  nsl_jtag.jtag.jtag_ate_i
      );
  end component;  
end package cbor_transactor;
