library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_output_se_divided is
  generic(
    divisor_c: positive := 1
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    port_o: out std_ulogic
    );
end entity;

architecture beh of clock_output_se_divided is
  
  type regs_t is
  record
    counter: integer range 0 to divisor_c-1;
  end record;

  signal r, rin: regs_t;
  signal pattern_s: std_ulogic_vector(0 to 1);

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.counter <= 0;
    end if;
  end process;

  transition: process(r) is
  begin
    rin <= r;

    if r.counter /= 0 then
      rin.counter <= r.counter - 1;
    else
      rin.counter <= divisor_c - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    pattern_s <= "11";

    -- We have a down-counter. First half of cycle is when counter is
    -- high
    if r.counter >= divisor_c / 2 then
      pattern_s <= "00";
    end if;

    if (divisor_c mod 2) = 1 then
      if r.counter = ((divisor_c - 1) / 2) then
        pattern_s <= "01";
      end if;
    end if;
  end process;

  needs_ddr: if (divisor_c mod 2) = 1
  generate
    signal clock_diff_s : nsl_io.diff.diff_pair;
  begin
    clock_diff_s <= nsl_io.diff.to_diff(clock_i);
    
    output: nsl_io.ddr.ddr_output
      port map(
        clock_i => clock_diff_s,
        d_i(0) => pattern_s(0),
        d_i(1) => pattern_s(1),
        dd_o => port_o
        );
  end generate;

  no_ddr: if (divisor_c mod 2) /= 1
  generate
    o_ff: process(clock_i) is
    begin
      if rising_edge(clock_i) then
        port_o <= pattern_s(0);
      end if;
    end process;
  end generate;
    
end architecture;
