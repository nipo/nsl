library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_simulation;
use nsl_clocking.pll.all;

entity tb is
end entity;

architecture arch of tb is

  constant mmcm_c : natural := nsl_clocking.pll_backend.pll_implementation_id("MMCM");
  constant pll_c : natural := nsl_clocking.pll_backend.pll_implementation_id("PLL");

begin

  main: process
    variable t : pll_topology_t;
    variable cfg : pll_config_t;
    variable m : pll_mapping_t;
  begin
    -- The PL of a Zynq-7000 carries the Series-7 clock managers, and
    -- their windows are the ones of the fabric it is built from.
    -- This is what a part table keyed on the Artix and Spartan
    -- prefixes alone misses.

    t := nsl_clocking.pll_backend.pll_topology_get(mmcm_c);
    assert t.vco_khz_min = 600_000 and t.vco_khz_max = 1_200_000
      and t.output_count = 7
      and t.pfd_khz_min = 10_000
      report "Bad MMCM topology"
      severity failure;

    t := nsl_clocking.pll_backend.pll_topology_get(pll_c);
    assert t.vco_khz_min = 800_000 and t.vco_khz_max = 1_600_000
      and t.output_count = 6
      and t.pfd_khz_min = 19_000
      report "Bad PLL topology"
      severity failure;

    -- The clock plan of example/digilent_arty_z7/pll_check, off the
    -- board's 125MHz crystal.  Four 12MHz outputs a quarter cycle
    -- apart, and the rack clock.

    cfg := pll_config(125_000_000,
                      pll_output(12_000_000),
                      pll_output(12_000_000, phase => (num => 1, den => 4)),
                      pll_output(12_000_000, phase => (num => 1, den => 2)),
                      pll_output(12_000_000, phase => (num => 3, den => 4)),
                      pll_output(100_000_000),
                      implementation => mmcm_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping for the phased clocks"
      severity failure;
    assert m.refdiv = 5 and m.fbdiv = (num => 36, den => 1)
      and m.pfd_khz = 25_000 and m.vco_khz = 900_000
      and m.output(0).divisor = (num => 75, den => 1)
      report "Unexpected mapping for the phased clocks"
      severity failure;

    -- The sampling side, on the other block: every rate divides
    -- 1050MHz and nothing else in the PLL window does, so the input
    -- divider has to be five here too.

    cfg := pll_config(125_000_000,
                      pll_output(87_500_000),
                      pll_output(150_000_000),
                      pll_output(50_000_000),
                      pll_output(25_000_000),
                      pll_output(10_000_000),
                      implementation => pll_c);
    m := nsl_clocking.pll_backend.pll_solve(cfg);
    report to_string(cfg) & ": " & to_string(m)
      severity note;
    assert m.valid
      report "No mapping for the sampling clocks"
      severity failure;
    assert m.refdiv = 5 and m.fbdiv = (num => 42, den => 1)
      and m.pfd_khz = 25_000 and m.vco_khz = 1_050_000
      and m.output(0).divisor = (num => 12, den => 1)
      and m.output(4).divisor = (num => 105, den => 1)
      report "Unexpected mapping for the sampling clocks"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
