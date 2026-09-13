library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding;

-- DVI protocol coding
package dvi is

  type symbol_vector_t is array (natural range 0 to 2) of nsl_line_coding.tmds.tmds_symbol_t;

  -- What a symbol period carries.  A link spends most of its time in
  -- PERIOD_CONTROL, and reaches data through a preamble and a guard
  -- band that say which kind of data follows.  Data islands are an
  -- HDMI addition; a DVI link only ever shows the video periods.
  type period_t is (
    PERIOD_CONTROL,
    PERIOD_DI_PRE,
    PERIOD_DI_GUARD,
    PERIOD_DI_DATA,
    PERIOD_VIDEO_PRE,
    PERIOD_VIDEO_GUARD,
    PERIOD_VIDEO_DATA
    );

end package dvi;
