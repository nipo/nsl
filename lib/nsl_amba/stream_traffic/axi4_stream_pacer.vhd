library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data, nsl_math, nsl_logic;
use work.axi4_stream.all;
use nsl_data.probability.all;
use nsl_logic.bool.all;

entity axi4_stream_pacer is
  generic(
    config_c : config_t;
    probability_denom_l2_c : integer range 1 to 31 := 7;
    probability_c : real := 0.95
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of axi4_stream_pacer is

  signal use_s, pass_su_s: std_ulogic;
  signal pass_s: boolean;
  
begin

  probability_streamer: nsl_data.probability.probability_stream_constant
    generic map(
      state_width_c => probability_denom_l2_c,
      probability_c => probability_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      ready_i => use_s,
      value_o => pass_su_s
      );

  pass_s <= pass_su_s = '1';
  use_s <= to_logic(is_valid(config_c, in_i) and is_ready(config_c, out_i));

  out_o <= transfer(config_c, in_i,
                    force_valid => true,
                    valid => is_valid(config_c, in_i) and pass_s);
  in_o <= accept(config_c, is_ready(config_c, out_i) and pass_s);

end architecture;
