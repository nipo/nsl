library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package interface is

  type framed_req is record
    data : framed_data_t;
    more : std_ulogic;
    val  : std_ulogic;
  end record;

  type framed_ack is record
    ack  : std_ulogic;
  end record;
  
end package interface;
