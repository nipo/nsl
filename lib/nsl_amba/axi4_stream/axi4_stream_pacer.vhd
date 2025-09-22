library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data, nsl_math;
use work.axi4_stream.all;
use nsl_data.prbs.all;

entity axi4_stream_pacer is
  generic(
    config_c : config_t;
    probability_denom_l2_c : natural range 1 to 31 := 7;
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

  subtype probability_t is unsigned(probability_denom_l2_c-1 downto 0);
  constant probability_threshold_i_c: integer
    := integer(probability_c * 2.0 ** probability_denom_l2_c);
  constant probability_threshold_il_c: integer
    := nsl_math.arith.min(2**probability_denom_l2_c-1, probability_threshold_i_c);
  constant probability_threshold_c : probability_t
    := to_unsigned(probability_threshold_il_c, probability_t'length);

  type regs_t is
  record
    prbs: prbs_state(30 downto 0);
    pass: boolean;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.prbs <= (others => '1');
      r.pass <= false;
    end if;
  end process;
  
  transition: process(r, in_i, out_i) is
    variable probability_v: probability_t;
    variable consumed: boolean;
  begin
    rin <= r;

    consumed := is_valid(config_c, in_i) and is_ready(config_c, out_i) and r.pass;

    if consumed or not r.pass then
      probability_v := unsigned(prbs_bit_string(r.prbs, prbs31, probability_v'length));
      rin.prbs <= prbs_forward(r.prbs, prbs31, probability_v'length);

      rin.pass <= probability_v <= probability_threshold_c;
    end if;
  end process;

  out_o <= transfer(config_c, in_i, force_valid => true, valid => is_valid(config_c, in_i) and r.pass);
  in_o <= accept(config_c, is_ready(config_c, out_i) and r.pass);

end architecture;
