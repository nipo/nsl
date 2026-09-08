library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, work, nsl_digilent, nsl_usb;
use nsl_digilent.pmod.all;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic;
    s_i: in std_ulogic_vector(1 to 2);

    j4_io: out nsl_digilent.pmod.pmod_double_t;

    uart_rx_i: in std_logic;
    uart_tx_o: out std_logic;

    usb_p_io: inout std_logic;
    usb_n_io: inout std_logic
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;
  signal clock_s, merged_reset_n_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal usb_c_s : nsl_usb.io.usb_io_c;
  signal usb_s_s : nsl_usb.io.usb_io_s;

begin

  usb_p_io <= usb_c_s.dp when usb_c_s.oe = '1' else 'Z';
  usb_n_io <= usb_c_s.dm when usb_c_s.oe = '1' else 'Z';
  usb_s_s.dp <= usb_p_io;
  usb_s_s.dm <= usb_n_io;

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  merged_reset_n_s <= internal_reset_n_s and not s_i(1);

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => merged_reset_n_s,
      data_o => reset_n_s
      );

  main: work.top.main
    generic map(
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      uart_i => uart_rx_i,
      uart_o => uart_tx_o,
      led_o(0) => done_led_o,
      led_o(1) => ready_led_o,

      usb_c_o => usb_c_s,
      usb_s_i => usb_s_s,

      pmod_dvi_o => j4_io
      );

end architecture;
