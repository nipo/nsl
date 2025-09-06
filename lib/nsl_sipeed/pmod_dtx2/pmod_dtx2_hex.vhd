library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_digilent, nsl_indication, work;
  
entity pmod_dtx2_hex is
  generic(
    clock_i_hz_c: integer;
    blink_rate_hz_c: integer := 100
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    
    value_i: in unsigned(7 downto 0);
    pmod_io: inout nsl_digilent.pmod.pmod_double_t
    );
end entity;

architecture beh of pmod_dtx2_hex is

  signal segment_s: nsl_indication.seven_segment.seven_segment_vector(0 to 1);

begin

  segment_s(0) <= nsl_indication.seven_segment.to_seven_segment(value_i(7 downto 4));
  segment_s(1) <= nsl_indication.seven_segment.to_seven_segment(value_i(3 downto 0));

  driver: work.pmod_dtx2.pmod_dtx2_driver
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      blink_rate_hz_c => blink_rate_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      value_i => segment_s,
      pmod_io => pmod_io
      );
  
end architecture;
