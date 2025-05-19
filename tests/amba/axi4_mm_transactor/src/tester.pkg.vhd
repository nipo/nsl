library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;

package tester is

  component tb is
    generic(
      beat_count_c : integer := 22
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      done_o : out std_ulogic
      );
  end component;

  component axi_transactor is
    generic (
      config_c: config_t;
      ctx_length_c : natural := 11
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      done_o : out std_ulogic;

      axi_o: out master_t;
      axi_i: in slave_t
      );
  end component;

end package;
