library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, nsl_i2c, work, nsl_digilent, nsl_sipeed;
use nsl_digilent.pmod.all;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic;
    s_i: in std_ulogic_vector(1 to 2);

    j4_io: out nsl_digilent.pmod.pmod_double_t;
    j5_io: inout nsl_digilent.pmod.pmod_double_t
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;
  signal clock_s, clock_reset_n_s : std_ulogic;
  signal button_s : std_ulogic_vector(0 to 3);
  
begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => clock_reset_n_s
      );

  pmod_btn: nsl_sipeed.pmod_btn_4_4.pmod_btn_4_4_input
    port map(
      pmod_io => j5_io,
      k_o => button_s
      );
  
  main: work.top.main
    generic map(
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => clock_reset_n_s,

      button_i => button_s,
      led_o(0) => done_led_o,
      led_o(1) => ready_led_o,

      pmod_dvi_o => j4_io
      );

end architecture;
