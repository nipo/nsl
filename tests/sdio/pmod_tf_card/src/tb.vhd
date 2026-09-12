library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_logic, nsl_digilent, nsl_sipeed, nsl_sdio;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.testing.all;

-- Checks the socket adapter of the Sipeed PMOD-TF-Card against the
-- pin mapping of its schematic, then runs a card model through
-- identification behind it.
--
-- The pin numbers below are the ones the schematic gives, written out
-- again here so that a mismatch with the adapter shows up as a failed
-- test rather than as a dead bus on a board.
entity tb is
end entity;

architecture beh of tb is

  constant clock_i_hz_c: natural := 100000000;
  constant clock_period_c: time := 10 ns;

  -- Time the adapter is told a contact takes to settle
  constant card_stable_us_c: natural := 20;
  constant card_stable_c: time := card_stable_us_c * 1 us;

  constant cmd_pin_c: natural := 2;
  constant clk_pin_c: natural := 4;
  constant det_pin_c: natural := 7;
  constant wp_pin_c: natural := 8;

  type pin_vector is array (natural range <>) of natural;
  constant dat_pin_c: pin_vector(0 to 3) := (3, 5, 6, 1);

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal half_cycle_m1_s: unsigned(7 downto 0) := x"01";
  signal sample_phase_s: unsigned(8 downto 0)
    := to_unsigned(default_sample_phase(clock_i_hz_c, 1), 9);
  signal run_s: std_ulogic := '0';

  signal drive_s, sample_s: std_ulogic;

  signal req_s: cmd_req_t := cmd_idle;
  signal req_ack_s: cmd_ack_t;
  signal rsp_s: cmd_rsp_t;

  signal host_o_s: sdio_master_o;
  signal host_i_s: sdio_master_i;
  signal card_present_s: std_ulogic;

  -- The connector, driven by the adapter, by whatever the socket side
  -- of the test puts there, and by the card model.
  signal pmod_s: nsl_digilent.pmod.pmod_double_t;
  signal socket_s: std_logic_vector(1 to 8) := (others => 'Z');

  -- Wires of the socket, as the board wires them to the connector
  signal card_bus_s: sdio_bus;
  signal card_o_s: sdio_slave_o;

begin

  clock_s <= (not clock_s) after clock_period_c / 2 when not done_s else '0';
  reset_n_s <= '1' after 3 * clock_period_c;

  pmod_s <= socket_s;

  -- Board side: the pull-ups of the four data lines and of the
  -- command line, and the card driving the same wires.
  pmod_s(cmd_pin_c) <= nsl_io.io.to_logic(card_o_s.cmd);
  pmod_s(cmd_pin_c) <= 'H';
  card_bus_s.cmd <= pmod_s(cmd_pin_c);
  card_bus_s.clk <= pmod_s(clk_pin_c);

  card_wiring: for i in dat_pin_c'range
  generate
    pmod_s(dat_pin_c(i)) <= nsl_io.io.to_logic(card_o_s.d(i));
    pmod_s(dat_pin_c(i)) <= 'H';
    card_bus_s.d(i) <= pmod_s(dat_pin_c(i));
  end generate;

  -- A socket has four data lines, and a card reads the ones it does
  -- not have as released.
  card_bus_s.d(card_bus_s.d'left downto 4) <= (others => 'H');

  pads: nsl_sipeed.pmod_tf_card.pmod_tf_card_pads
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      card_stable_us_c => card_stable_us_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pmod_io => pmod_s,

      sdio_i => host_o_s,
      sdio_o => host_i_s,

      card_present_o => card_present_s
      );

  clock_driver: nsl_sdio.link.link_clock_driver
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      half_cycle_m1_i => half_cycle_m1_s,
      sample_phase_i => sample_phase_s,
      run_i => run_s,

      clk_o => host_o_s.clk,
      drive_o => drive_s,
      sample_o => sample_s,
      running_o => open
      );

  engine: nsl_sdio.link.link_cmd_engine
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      drive_i => drive_s,
      sample_i => sample_s,

      cmd_o => host_o_s.cmd,
      cmd_i => host_i_s.cmd,
      dat0_i => host_i_s.d(0),

      req_i => req_s,
      req_o => req_ack_s,

      rsp_o => rsp_s,
      busy_o => open
      );

  card: nsl_sdio.testing.testing_card_model
    port map(
      sdio_i => to_slave_i(card_bus_s),
      sdio_o => card_o_s
      );

  stim: process is

    variable status: cmd_status_t;

    procedure command(index: natural;
                      argument: unsigned;
                      response: response_kind_t;
                      check_crc: boolean := true) is
    begin
      req_s <= cmd_request(index, argument, response, check_crc);

      loop
        wait until rising_edge(clock_s);
        exit when req_ack_s.ready = '1';
      end loop;

      req_s <= cmd_idle;

      loop
        wait until rising_edge(clock_s);
        exit when rsp_s.valid = '1';
      end loop;

      status := rsp_s.status;

      assert status = CMD_OK
        report "CMD" & to_string(index) & " ended as "
        & cmd_status_t'image(status)
        severity failure;
    end procedure;

  begin
    wait until reset_n_s = '1';

    -- Card detect, which the socket takes low while a card is in.
    -- What comes out of the adapter has settled, so it takes the time
    -- the adapter was told a contact takes.
    socket_s(det_pin_c) <= '1';
    wait for 4 * card_stable_c;
    assert card_present_s = '0'
      report "adapter sees a card in an empty socket" severity failure;

    socket_s(det_pin_c) <= '0';
    wait for 4 * card_stable_c;
    assert card_present_s = '1'
      report "adapter sees no card while the socket says there is one"
      severity failure;

    -- A contact that has not held still yet says nothing new
    socket_s(det_pin_c) <= '1';
    wait for card_stable_c / 4;
    socket_s(det_pin_c) <= '0';
    wait for 4 * card_stable_c;
    assert card_present_s = '1'
      report "a contact that bounced once unseated a card" severity failure;

    assert pmod_s(wp_pin_c) = 'Z'
      report "adapter drives the write protect pin, which the board ties high"
      severity failure;

    -- Data lines, one at a time in both directions, so a swapped pair
    -- cannot pass.
    host_o_s.d <= (others => nsl_io.io.tristated_z);

    for i in dat_pin_c'range
    loop
      socket_s(dat_pin_c(i)) <= '0';
      wait for clock_period_c;

      for j in dat_pin_c'range
      loop
        assert host_i_s.d(j) = if_else(i = j, '0', '1')
          report "socket pin " & to_string(dat_pin_c(i))
          & " taken low reads as " & to_string(host_i_s.d(j))
          & " on data line " & to_string(j)
          severity failure;
      end loop;

      socket_s(dat_pin_c(i)) <= 'Z';
      wait for clock_period_c;
    end loop;

    for i in dat_pin_c'range
    loop
      host_o_s.d <= (others => nsl_io.io.tristated_z);
      host_o_s.d(i) <= nsl_io.io.to_tristated('0');
      wait for clock_period_c;

      for j in dat_pin_c'range
      loop
        assert to_x01(pmod_s(dat_pin_c(j))) = if_else(i = j, '0', '1')
          report "data line " & to_string(i) & " driven low reads as "
          & to_string(to_x01(pmod_s(dat_pin_c(j))))
          & " on socket pin " & to_string(dat_pin_c(j))
          severity failure;
      end loop;
    end loop;

    host_o_s.d <= (others => nsl_io.io.tristated_z);

    -- Then the command line and DAT0 for real, through a card.
    run_s <= '1';

    command(0, x"00000000", RESP_NONE);
    command(8, x"000001aa", RESP_SHORT);

    loop
      command(55, x"00000000", RESP_SHORT);
      command(41, x"40ff8000", RESP_SHORT, false);
      exit when rsp_s.payload(31) = '1';
    end loop;

    command(2, x"00000000", RESP_LONG);
    command(3, x"00000000", RESP_SHORT);
    command(7, x"12340000", RESP_SHORT_BUSY);

    report "sdio pmod tf card test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
