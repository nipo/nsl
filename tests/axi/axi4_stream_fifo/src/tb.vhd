library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
begin

  b: process
    use nsl_axi.axi4_stream.all;
    constant context: log_context := "AXIS";

    constant c: config_t := config(4, last => true);
    variable t: transfer_t;
  begin
    log_info(context, to_string(c));

    t := transfer(c, from_hex("deadbeef"));
    log_info(context, to_string(c, t));

    log_info(context, "done");
    wait;
  end process;

  a: process
    use nsl_axi.axi4_stream.all;
    constant context: log_context := "AXISwK";

    constant c: config_t := config(4, last => true, keep => true);
    variable t: transfer_t;
  begin
    log_info(context, to_string(c));

    t := transfer(c, from_hex("deadbeef"), keep => x"4");
    log_info(context, to_string(c, t));

    log_info(context, "done");
    wait;
  end process;
  
end;
