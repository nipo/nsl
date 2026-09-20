library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

-- Pin side of a single data rate SDRAM controller.
--
-- One phase, one edge per controller cycle, so the memory clock is the
-- controller clock and a DFI slot maps straight onto a pin.  What is
-- left to an implementation is how commands reach the pads, how read
-- data is captured, and how long that takes.
package sdram_io is

  component sdram_phy is
    generic(
      part_c: dram_part_t;
      timing_c: dram_timing_t;
      dfi_config_c: config_t;
      -- Controller cycles a read takes on top of the part's CAS
      -- latency.  Raise it when the board's round trip no longer fits
      -- inside a cycle.
      capture_ck_c: natural := 2;
      capture_on_fall_c: boolean := true
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      dfi_i: in master_t;
      dfi_o: out slave_t;

      clock_o: out std_ulogic;
      cke_o: out std_ulogic;
      cs_n_o: out std_ulogic;
      ras_n_o: out std_ulogic;
      cas_n_o: out std_ulogic;
      we_n_o: out std_ulogic;
      ba_o: out unsigned;
      a_o: out unsigned;
      dqm_o: out std_ulogic_vector;
      dq_o: out nsl_io.io.tristated_vector;
      dq_i: in std_ulogic_vector
      );
  end component;

end package sdram_io;
