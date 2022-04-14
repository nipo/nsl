library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PLL abstraction.
--
-- Vendor clocking resources usually offer PLLs but
-- they are quite cumbersome to use most of the time because:
--
-- - feedback path is vendor specific and depends on the chip lineup,
--
-- - VCO locking range is chip-specific,
--
-- - There are various competing blocks with different interface for
--   the same service,
--
-- - There are some arbitrary offsets and encodings in dividors that
--   are not obvious from the port and generic names.
--
-- This package gives a simple interface for simple case: one input
-- clock of fixed frequency and one output clock of fixed
-- frequency. This is the minimal service every PLL allows to
-- implement.
--
-- VCO parameters and PLL implementation are taken care of
-- automatically.
--
-- For other instantiation cases (multiple outputs, phase shifts,
-- etc), user should fallback to vendor libraries as there is no
-- common feature.
package pll is

  -- hw_variant_c are a list of parameters to specify hardware-specific hints.
  -- They are in the form "target1(param=value,token) target2(param=value)"
  --
  -- Available targets:
  -- - "series67(type=...)"
  --     type: "pll" or "dcm": Use a PLL or a DCM block, defaults to PLL
  -- - "ice40(in=...,out=...)"
  --     in: "core" or "pad": Use PLL40_CORE or PLL40_PAD, defaults to pad
  --     out: "core" or "global": Output clock port selection, defaults to global
  -- - "machxo2()"
  --     none.
  -- - "simulation()"
  --     none.
  --
  -- You may specify multiple parameter sets for different architectures, this
  -- way, design will be portable across those targets.
  component pll_basic
    generic(
      input_hz_c  : natural;
      output_hz_c : natural;
      hw_variant_c : string := ""
      );
    port(
      clock_i    : in  std_ulogic;
      clock_o    : out std_ulogic;

      reset_n_i  : in  std_ulogic;
      locked_o   : out std_ulogic
      );
  end component;

end package pll;
