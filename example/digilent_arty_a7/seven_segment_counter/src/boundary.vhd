library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_digilent, nsl_sipeed, nsl_clocking;

entity boundary is
  port (
    clock_100_i: in std_logic;
    ja_io: inout nsl_digilent.pmod.pmod_double_t;
    jb_io: inout nsl_digilent.pmod.pmod_double_t;
    btn_i: in std_logic_vector(0 to 3)
  );
end boundary;

architecture arch of boundary is

  signal clock_s, reset_n_s: std_ulogic;
  signal pressed_s: std_ulogic_vector(btn_i'range);

  type regs_t is
  record
    counter: unsigned(7 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_100_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  deglitchers: for i in btn_i'range
  generate
    ai: nsl_clocking.async.async_input
      generic map(
        debounce_count_c => 10_000
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        data_i => btn_i(i),
        falling_o => pressed_s(i)
        );
  end generate;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.counter <= x"00";
    end if;
  end process;

  transition: process(r, pressed_s) is
  begin
    rin <= r;

    if pressed_s(1) = '1' then
      rin.counter <= r.counter - 1;
    end if;

    if pressed_s(2) = '1' then
      rin.counter <= r.counter + 1;
    end if;
  end process;

  ss: nsl_sipeed.pmod_dtx2.pmod_dtx2_hex
    generic map(
      clock_i_hz_c => 100_000_000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      value_i => r.counter,
      pmod_io => ja_io
      );

  led: nsl_sipeed.pmod_8xled.pmod_8xled_driver
    port map(
      led_i => std_ulogic_vector(r.counter),
      pmod_io => jb_io
      );
  
end arch;
