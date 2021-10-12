library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding;

package dvi is

  type symbol_vector_t is array (natural range 0 to 2) of nsl_line_coding.tmds.tmds_symbol_t;

end package dvi;
