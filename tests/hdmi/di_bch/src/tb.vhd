library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_hdmi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_hdmi.encoder.all;

entity tb is
end tb;

architecture arch of tb is

begin

  hdmi_bch: process
    constant context: log_context := "HDMI DI BCH";
    constant di_bch_init_c : di_bch_t := x"00";
  begin
    assert_equal(context, "header",
                 std_ulogic_vector(di_bch(di_bch_init_c, x"deadbe")),
                 x"ea",
                 failure);

    assert_equal(context, "subpacket",
                 std_ulogic_vector(di_bch(di_bch_init_c, x"deadbeefdecafb")),
                 x"e5",
                 failure);

    log_info(context, "done");
    wait;
  end process;
  
end;
