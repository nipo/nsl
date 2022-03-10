library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_inet.ethernet.all;

entity tb is
end tb;

architecture arch of tb is
begin

  ieee_802_3: process
    constant context: log_context := "IEEE-802.3";
    constant data : byte_string := from_hex( "20cf301acea16238e0c2bd3008060001"
                                            &"0800060400016238e0c2bd300a2a2a01"
                                            &"0000000000000a2a2a02000000000000"
                                            &"00000000000000000000000022b72660");
  begin
    
    assert_equal(context, "compare",
                 crc_spill(fcs_params_c, crc_update(fcs_params_c, crc_init(fcs_params_c), data(0 to 59))),
                 data(60 to 63),
                 failure);

    assert_equal(context, "check constant",
                 unsigned(crc_update(fcs_params_c, crc_init(fcs_params_c), data)),
                 unsigned(crc_check(fcs_params_c)),
                 failure);

    log_info(context, "done");
    wait;
  end process;
  
end;
