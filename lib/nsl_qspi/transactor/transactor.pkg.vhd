library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_qspi, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

package transactor is

  -- Every command frame is one CS assertion. A mandatory four-byte
  -- header is followed by zero or more independent phases. All counts
  -- are unsigned bytes.
  -- 
  -- Only the final command byte has ``last=1``. CS remains asserted
  -- across all phases. Helpers ``qspi_timing``, ``qspi_tx``,
  -- ``qspi_rx``, ``qspi_dummy`` return concatenable byte strings;
  -- zero dummy cycles yields an empty string.

  -- ``01 divider_minus_one setup_minus_one high_minus_one``: frame header.
  -- Timing units are system-clock cycles, each in 1..256. Divider is the SCK
  -- half-period; setup is the minimum CS-to-first-clock time; high is minimum
  -- CS-high time before completion and admission of another command.
  constant qspi_cmd_timing_c: byte := x"01";
  -- ``10 count_minus_one payload...``: transmit 1..256 bytes on one lane.
  constant qspi_cmd_tx1_c: byte := x"10";
  -- ``11 count_minus_one payload...``: transmit 1..256 bytes on four lanes.
  constant qspi_cmd_tx4_c: byte := x"11";
  -- ``20 count_minus_one``: receive 1..256 bytes on one lane.
  constant qspi_cmd_rx1_c: byte := x"20";
  -- ``21 count_minus_one``: receive 1..256 bytes on four lanes.
  constant qspi_cmd_rx4_c: byte := x"21";
  -- ``30 cycles_minus_one``: release DQ for 1..256 complete clock cycles.
  constant qspi_cmd_dummy_c: byte := x"30";

  -- A response frame contains all received bytes, in phase order, followed by
  -- one status byte with ``last=1``: ``00`` success, ``01`` malformed command.
  constant qspi_status_ok_c: byte := x"00";
  constant qspi_status_error_c: byte := x"01";
  constant qspi_command_max_c: positive := 512;
  constant qspi_response_max_c: positive := 256;

  function qspi_timing(divider: positive := 1;
                       cs_setup: positive := 1;
                       cs_high: positive := 1) return byte_string;
  function qspi_tx(data: byte_string; quad: boolean := false) return byte_string;
  function qspi_rx(count: positive; quad: boolean := false) return byte_string;
  function qspi_dummy(cycles: natural) return byte_string;

  -- No-read commands also return a one-byte completion frame. Maximum
  -- command length is 512 bytes; maximum aggregate read length is 256
  -- bytes.
  --
  -- Commands are buffered and validated before CS is
  -- asserted. Unknown opcodes, truncated headers/counts/payloads,
  -- oversized commands or read totals produce only an error
  -- completion, without pin activity. Oversized input is drained
  -- through ``last``. An unterminated input cannot assert CS; the
  -- producer must eventually supply ``last`` or reset. Response
  -- backpressure never holds CS low.
  --
  -- Reset aborts all activity and releases CS and DQ. Inter-phase
  -- clock-low gaps are permitted. All ready/valid outputs remain
  -- stable under backpressure.  The simple implementation statically
  -- buffers up to 512 command bytes and 256 response
  -- bytes. Integrations sensitive to register or memory cost should
  -- take this storage requirement into account.
  component qspi_framed_transactor is
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      qspi_o: out nsl_qspi.qspi.qspi_master_o;
      qspi_i: in nsl_qspi.qspi.qspi_master_i;

      cmd_i: in nsl_bnoc.framed.framed_req;
      cmd_o: out nsl_bnoc.framed.framed_ack;
      rsp_o: out nsl_bnoc.framed.framed_req;
      rsp_i: in nsl_bnoc.framed.framed_ack
      );
  end component;
end package;

package body transactor is
  function qspi_timing(divider: positive := 1;
                       cs_setup: positive := 1;
                       cs_high: positive := 1) return byte_string is
  begin
    assert divider <= 256 and cs_setup <= 256 and cs_high <= 256 severity failure;
    return byte_string'(
      qspi_cmd_timing_c,
      std_ulogic_vector(to_unsigned(divider-1, 8)),
      std_ulogic_vector(to_unsigned(cs_setup-1, 8)),
      std_ulogic_vector(to_unsigned(cs_high-1, 8)));
  end function;

  function qspi_tx(data: byte_string; quad: boolean := false) return byte_string is
  begin
    assert data'length >= 1 and data'length <= 256 severity failure;
    if quad then
      return byte_string'(
        qspi_cmd_tx4_c,
        std_ulogic_vector(to_unsigned(data'length-1, 8))) & data;
    end if;
    return byte_string'(
      qspi_cmd_tx1_c,
      std_ulogic_vector(to_unsigned(data'length-1, 8))) & data;
  end function;

  function qspi_rx(count: positive; quad: boolean := false) return byte_string is
  begin
    assert count <= 256 severity failure;
    if quad then
      return byte_string'(qspi_cmd_rx4_c, std_ulogic_vector(to_unsigned(count-1, 8)));
    end if;
    return byte_string'(qspi_cmd_rx1_c, std_ulogic_vector(to_unsigned(count-1, 8)));
  end function;

  function qspi_dummy(cycles: natural) return byte_string is
  begin
    assert cycles <= 256 severity failure;
    if cycles = 0 then
      return null_byte_string;
    end if;
    return byte_string'(qspi_cmd_dummy_c, std_ulogic_vector(to_unsigned(cycles-1, 8)));
  end function;
end package body;
