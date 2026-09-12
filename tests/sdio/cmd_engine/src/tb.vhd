library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_sdio;
use nsl_data.text.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.testing.all;

-- Runs the command line of a host against a card model, over the
-- identification sequence a host walks through, at the three bus
-- clock divisors such a sequence uses.
--
-- The model answers a while after the rising edge that carries its
-- answer, the way a card does, so a pass means the host samples its
-- inputs where a card has put something there.
entity tb is
end entity;

architecture beh of tb is

  constant clock_i_hz_c: natural := 100000000;
  constant clock_period_c: time := 10 ns;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal half_cycle_m1_s: unsigned(7 downto 0) := x"04";
  signal sample_phase_s: unsigned(8 downto 0) := "000000000";
  signal run_s: std_ulogic := '0';

  signal drive_s, sample_s: std_ulogic;
  signal clk_s: std_ulogic;

  signal req_s: cmd_req_t := cmd_idle;
  signal req_ack_s: cmd_ack_t;
  signal rsp_s: cmd_rsp_t;
  signal busy_s: std_ulogic;

  signal host_cmd_s: nsl_io.io.tristated;
  signal host_o_s: sdio_master_o;
  signal host_i_s: sdio_master_i;
  signal card_o_s: sdio_slave_o;
  signal bus_s: sdio_bus;

  -- Last token the host put on the wires, as the wires carried it
  signal token_s: std_ulogic_vector(47 downto 0) := (others => '0');
  signal token_count_s: natural := 0;

  -- Set as soon as the host has seen a card hold DAT0 low
  signal busy_seen_s: boolean := false;

begin

  clock_s <= (not clock_s) after clock_period_c / 2 when not done_s else '0';
  reset_n_s <= '1' after 3 * clock_period_c;

  -- Both ends drive the wires, and the pull-ups hold them while
  -- neither does.
  bus_s <= to_bus(host_o_s);
  bus_s <= to_bus(card_o_s);
  bus_s <= sdio_bus_released_c;

  host_o_s.clk <= clk_s;
  host_o_s.cmd <= host_cmd_s;
  host_o_s.d <= (others => nsl_io.io.tristated_z);
  host_i_s <= to_master_i(bus_s);

  clock_driver: nsl_sdio.link.link_clock_driver
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      half_cycle_m1_i => half_cycle_m1_s,
      sample_phase_i => sample_phase_s,
      run_i => run_s,

      clk_o => clk_s,
      drive_o => drive_s,
      sample_o => sample_s,
      running_o => open
      );

  dut: nsl_sdio.link.link_cmd_engine
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      drive_i => drive_s,
      sample_i => sample_s,

      cmd_o => host_cmd_s,
      cmd_i => host_i_s.cmd,
      dat0_i => host_i_s.d(0),

      req_i => req_s,
      req_o => req_ack_s,

      rsp_o => rsp_s,
      busy_o => busy_s
      );

  card: nsl_sdio.testing.testing_card_model
    port map(
      sdio_i => to_slave_i(bus_s),
      sdio_o => card_o_s
      );

  -- Collects what the host drives on the command line, to have the
  -- tokens checked against known ones rather than against what the
  -- model believes.
  monitor: process is
    variable token: std_ulogic_vector(47 downto 0);
    variable count: natural;
  begin
    loop
      count := 0;

      while host_cmd_s.en /= '1'
      loop
        wait on host_cmd_s;
      end loop;

      while host_cmd_s.en = '1'
      loop
        wait until rising_edge(clk_s) or host_cmd_s.en /= '1';

        if host_cmd_s.en = '1' then
          token := token(46 downto 0) & to_x01(bus_s.cmd);
          count := count + 1;
        end if;
      end loop;

      assert count = 48
        report "host drove the command line for " & to_string(count)
        & " periods instead of 48"
        severity failure;

      token_s <= token;
      token_count_s <= token_count_s + 1;
    end loop;
  end process;

  busy_watch: process is
  begin
    wait until busy_s = '1';
    busy_seen_s <= true;
  end process;

  stim: process is

    variable status: cmd_status_t;
    variable payload: std_ulogic_vector(127 downto 0);
    variable rca: unsigned(15 downto 0);

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
      payload := rsp_s.payload;
    end procedure;

    procedure check_status(want: cmd_status_t; what: string) is
    begin
      assert status = want
        report what & " ended as " & cmd_status_t'image(status)
        & " instead of " & cmd_status_t'image(want)
        severity failure;
    end procedure;

    procedure check_token(want: std_ulogic_vector; what: string) is
    begin
      assert token_s = want
        report what & " went out as " & to_string(token_s)
        & " instead of " & to_string(want)
        severity failure;
    end procedure;

    -- Walks a card from power-up to the state where it takes data
    -- commands, which is the sequence a host has to get right before
    -- anything else can be tried.
    procedure identify is
    begin
      command(0, x"00000000", RESP_NONE);
      check_status(CMD_OK, "CMD0");
      -- A host with no card would see this exact token, which is the
      -- one every bus starts with.
      check_token(x"400000000095", "CMD0");

      command(8, x"000001aa", RESP_SHORT);
      check_status(CMD_OK, "CMD8");
      check_token(x"48000001aa87", "CMD8");
      assert payload(31 downto 0) = x"000001aa"
        report "CMD8 did not echo the voltage and pattern asked for"
        severity failure;

      -- The operating conditions come back without a meaningful
      -- checksum, so a host that checks it anyway must say so.
      command(55, x"00000000", RESP_SHORT);
      check_status(CMD_OK, "CMD55");
      command(41, x"40ff8000", RESP_SHORT);
      check_status(CMD_CRC_ERROR, "ACMD41 checked for a checksum it has not");

      -- Then poll it properly until the card is done powering up.
      loop
        command(55, x"00000000", RESP_SHORT);
        check_status(CMD_OK, "CMD55");
        command(41, x"40ff8000", RESP_SHORT, false);
        check_status(CMD_OK, "ACMD41");
        exit when payload(31) = '1';
      end loop;

      assert payload(30) = '1'
        report "card does not claim high capacity addressing"
        severity failure;

      command(2, x"00000000", RESP_LONG);
      check_status(CMD_OK, "CMD2");
      assert payload = card_register(default_cid_c)
        report "CMD2 answered " & to_string(payload)
        & " instead of " & to_string(card_register(default_cid_c))
        severity failure;

      command(3, x"00000000", RESP_SHORT);
      check_status(CMD_OK, "CMD3");
      rca := unsigned(payload(31 downto 16));
      assert rca = x"1234"
        report "card handed out address " & to_string(rca)
        severity failure;

      command(9, rca & x"0000", RESP_LONG);
      check_status(CMD_OK, "CMD9");
      assert payload = csd_v2(65536)
        report "CMD9 answered " & to_string(payload)
        severity failure;

      -- Selecting a card leaves it busy on DAT0 for a while, which
      -- the host has to wait through before it reports the answer.
      command(7, rca & x"0000", RESP_SHORT_BUSY);
      check_status(CMD_OK, "CMD7");
      assert busy_seen_s
        report "host did not see the card hold DAT0 low"
        severity failure;

      command(16, x"00000200", RESP_SHORT);
      check_status(CMD_OK, "CMD16");

      command(55, rca & x"0000", RESP_SHORT);
      check_status(CMD_OK, "CMD55");
      command(6, x"00000002", RESP_SHORT);
      check_status(CMD_OK, "ACMD6");
    end procedure;

    -- Bus clock divisors and where each of them has to sample
    type divisor_vector is array (natural range <>) of natural;
    constant divisor_c: divisor_vector := (4, 1, 0);

  begin
    wait until reset_n_s = '1';

    for i in divisor_c'range
    loop
      half_cycle_m1_s <= to_unsigned(divisor_c(i), half_cycle_m1_s'length);
      sample_phase_s <= to_unsigned(default_sample_phase(clock_i_hz_c,
                                                         divisor_c(i)),
                                    sample_phase_s'length);
      run_s <= '1';

      report "identification at a bus period of "
        & to_string(2 * (divisor_c(i) + 1)) & " fabric cycles, sampling at "
        & to_string(default_sample_phase(clock_i_hz_c, divisor_c(i)))
        severity note;

      identify;

      -- A command addressed to another card goes unanswered, which
      -- is the only way a bus tells a host that nothing is there.
      command(13, x"43210000", RESP_SHORT);
      check_status(CMD_TIMEOUT, "CMD13 to an address no card has");

      -- Same for the command a host uses to find out whether a card
      -- holds anything besides memory.
      command(5, x"00000000", RESP_SHORT);
      check_status(CMD_TIMEOUT, "CMD5 to a card holding memory only");

      -- Stopping the clock between commands is how a host makes a
      -- card wait, and nothing may come out of it.
      run_s <= '0';
      wait for 20 * clock_period_c;
      assert clk_s = '0'
        report "clock did not stop low" severity failure;
      run_s <= '1';

      command(13, x"12340000", RESP_SHORT);
      check_status(CMD_OK, "CMD13 after a stopped clock");

      -- Back to the top of the sequence for the next divisor.
      run_s <= '0';
    end loop;

    assert token_count_s > 30
      report "monitor only saw " & to_string(token_count_s) & " tokens"
      severity failure;

    report "sdio command engine test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
