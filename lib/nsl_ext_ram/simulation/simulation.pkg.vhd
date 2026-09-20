library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;

-- Behavioural models of external memory devices.
--
-- Models answer like the part they stand for and, more usefully,
-- complain when the controller driving them breaks a datasheet
-- constraint.  Timing is checked against the picosecond values of
-- dram_part_t, not against tick counts, so a controller that gets its
-- clock period wrong is caught too.
--
-- Storage is sparse: pages are allocated on first write, and a read of
-- a location that was never written returns 'U'.
--
-- Every model counts the constraints it saw broken on violation_count_o,
-- because a datasheet check reported and not counted cannot fail a run,
-- and a bench that cannot fail is not a check of anything.
package simulation is

  component sdram_model is
    generic(
      part_c: dram_part_t;
      check_timing_c: boolean := true;
      -- Clock to data out, and how long data stays valid past an edge
      tac_ps_c: natural := 5400;
      toh_ps_c: natural := 2500;
      -- Command, address and write data setup and hold
      tis_ps_c: natural := 1500;
      tih_ps_c: natural := 800
      );
    port(
      clock_i: in std_ulogic;
      cke_i: in std_ulogic;
      cs_n_i: in std_ulogic;
      ras_n_i: in std_ulogic;
      cas_n_i: in std_ulogic;
      we_n_i: in std_ulogic;
      ba_i: in unsigned;
      a_i: in unsigned;
      dqm_i: in std_ulogic_vector;

      dq_i: in std_ulogic_vector;
      dq_o: out nsl_io.io.tristated_vector;

      violation_count_o: out natural
      );
  end component;

  component sram_model is
    generic(
      part_c: sram_part_t;
      check_timing_c: boolean := true
      );
    port(
      clock_i: in std_ulogic;
      cs_n_i: in std_ulogic;
      cen_n_i: in std_ulogic;
      we_n_i: in std_ulogic;
      bw_n_i: in std_ulogic_vector;
      oe_n_i: in std_ulogic;
      a_i: in unsigned;

      dq_i: in std_ulogic_vector;
      dq_o: out nsl_io.io.tristated_vector;
      dqp_i: in std_ulogic_vector;
      dqp_o: out nsl_io.io.tristated_vector;

      violation_count_o: out natural
      );
  end component;

end package simulation;
