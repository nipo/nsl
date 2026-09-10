library ieee;
use ieee.std_logic_1164.all;

use work.pll.all;

-- pll_basic realized over pll_multi, for backends that have one.
entity pll_basic is
  generic(
    input_hz_c  : natural;
    output_hz_c : natural
    );
  port(
    clock_i    : in  std_ulogic;
    clock_o    : out std_ulogic;

    reset_n_i  : in  std_ulogic;
    locked_o   : out std_ulogic
    );
end entity;

architecture wrapper of pll_basic is

  -- Exact or fail: a rate the PLL cannot reach exactly fails
  -- elaboration instead of silently approximating.
  constant config_c : pll_config_t := pll_config(
    input_hz => input_hz_c,
    o0 => pll_output(output_hz_c));

  signal clock_s : std_ulogic_vector(0 to 0);

begin

  no_pll: if input_hz_c = output_hz_c generate
    clock_o <= clock_i;
    locked_o <= reset_n_i;
  end generate;

  has_pll: if input_hz_c /= output_hz_c generate
    inst: work.pll.pll_multi
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        clock_o => clock_s,
        reset_n_i => reset_n_i,
        locked_o => locked_o
        );
    clock_o <= clock_s(0);
  end generate;

end architecture wrapper;
