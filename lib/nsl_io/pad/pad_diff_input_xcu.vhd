library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

-- UltraScale / UltraScale+ differential input.
--
-- UltraScale has no dedicated global-clock input buffer (IBUFGDS is only
-- a retarget of IBUFDS), so is_clock does not change the primitive: clock
-- routing is done by the BUFG the caller puts behind this pad.
--
-- On UltraScale HP banks the internal termination is not set through the
-- primitive's DIFF_TERM generic but with the DIFF_TERM_ADV property
-- (e.g. "set_property DIFF_TERM_ADV TERM_100 [get_ports ...]").  The
-- diff_term generic is therefore not forwarded here; termination must be
-- set in the constraints.
--
-- Callers should still pass diff_term => false: Vivado reads a module
-- parameter named DIFF_TERM as the I/O property, and with true it emits
-- Constraints 18-5254 ("DIFF_TERM is not supported in UltraScale devices")
-- during synthesis constraint validation.
entity pad_diff_input is
  generic(
    diff_term : boolean := true;
    is_clock  : boolean := false;
    invert    : boolean := false
    );
  port(
    p_diff : in diff_pair;
    p_se   : out std_ulogic
    );
end entity;

architecture rtl of pad_diff_input is

  attribute BOX_TYPE : string;

  -- UG974: on UltraScale, IOSTANDARD, DIFF_TERM, IBUF_LOW_PWR are port
  -- properties (XDC), not primitive attributes. Declare no generics so
  -- synthesis does not attach them to the cell.
  component IBUFDS
    port (
      O : out std_ulogic;
      I : in std_ulogic;
      IB : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IBUFDS : component is "PRIMITIVE";

  signal s_se : std_ulogic;

begin

  diff_input : ibufds
    port map(
      i  => p_diff.p,
      ib => p_diff.n,
      o  => s_se
      );

  p_se <= s_se when not invert else (not s_se);

end architecture;
