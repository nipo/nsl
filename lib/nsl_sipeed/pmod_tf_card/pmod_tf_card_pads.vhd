library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_digilent, nsl_io, nsl_sdio;

entity pmod_tf_card_pads is
  generic(
    clock_i_hz_c: natural;
    card_stable_us_c: natural := 100000
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    pmod_io: inout nsl_digilent.pmod.pmod_double_t;

    sdio_i: in nsl_sdio.sdio.sdio_master_o;
    sdio_o: out nsl_sdio.sdio.sdio_master_i;

    card_present_o: out std_ulogic
    );
end entity;

architecture beh of pmod_tf_card_pads is

  type pin_vector is array (natural range <>) of natural;

  -- PMOD pin each data line of the socket lands on
  constant dat_pin_c: pin_vector(0 to 3) := (3, 5, 6, 1);

  signal card_detect_s: std_ulogic;

begin

  pmod_io(4) <= sdio_i.clk;

  cmd_driver: nsl_io.io.tristated_io_driver
    port map(
      v_i => sdio_i.cmd,
      v_o => sdio_o.cmd,
      io_io => pmod_io(2)
      );

  dat_driver: for i in dat_pin_c'range
  generate
    driver: nsl_io.io.tristated_io_driver
      port map(
        v_i => sdio_i.d(i),
        v_o => sdio_o.d(i),
        io_io => pmod_io(dat_pin_c(i))
        );
  end generate;

  sdio_o.d(sdio_o.d'left downto 4) <= (others => '1');

  -- An unwired socket leaves this floating, which reads as neither
  -- value and leaves the debouncer at the one it starts from.
  card_detect_s <= not to_x01(pmod_io(7));

  -- The contact bounces, and pushing a card in wipes it for a while,
  -- so what comes out of here has held still.
  card_detect: nsl_clocking.async.async_debouncer
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      stable_us_c => card_stable_us_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => card_detect_s,
      data_o => card_present_o
      );

  -- A microSD card has no write protect notch, so the socket has
  -- nothing to report there and the board ties the pin high.
  pmod_io(8) <= 'Z';

end architecture;
