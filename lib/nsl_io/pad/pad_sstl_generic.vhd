library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

-- A pseudo-differential pair is two ordinary pins driven against each
-- other; what makes it SSTL is the standard the pins are constrained
-- to, not the logic behind them.
entity pad_sstl_diff_output is
  generic(
    standard_c: nsl_io.pad.sstl_standard_t
    );
  port(
    v_i: in std_ulogic;
    pad_o: out nsl_io.diff.diff_pair
    );
end entity;

architecture generic_impl of pad_sstl_diff_output is
begin
  pad_o.p <= v_i;
  pad_o.n <= not v_i;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity pad_sstl_diff_io is
  generic(
    standard_c: nsl_io.pad.sstl_standard_t
    );
  port(
    v_i: in nsl_io.io.tristated;
    v_o: out std_ulogic;
    pad_o: out nsl_io.io.tristated_vector(0 to 1);
    pad_i: in std_ulogic_vector(0 to 1)
    );
end entity;

architecture generic_impl of pad_sstl_diff_io is
begin
  pad_o(0) <= v_i;
  pad_o(1) <= nsl_io.io."not"(v_i);
  -- The true half carries the value; a receiver that can tell the two
  -- apart belongs in a vendor specific implementation.
  v_o <= pad_i(0);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity pad_sstl_input is
  generic(
    standard_c: nsl_io.pad.sstl_standard_t
    );
  port(
    pad_i: in std_ulogic;
    v_o: out std_ulogic
    );
end entity;

architecture generic_impl of pad_sstl_input is
begin
  v_o <= pad_i;
end architecture;
