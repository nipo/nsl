library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.sram.all;

-- Runs whole bursts through a synchronous SRAM controller and its pin
-- logic, against the part model, over a board that takes time to
-- cross.
--
-- The flight time is the point of the bench.  Command pins and the
-- forwarded clock travel together, so what the part sees is the half
-- period of setup and hold the clock forwarding was chosen for; read
-- data travels back on its own and has to land inside the cycle the
-- controller captures on.  The model says so in picoseconds if it does
-- not.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: sram_part_t := cy7c1462av25_c;
  constant tck_ps_c: natural := 20000;
  constant tck_c: time := tck_ps_c * 1 ps;
  constant burst_cycle_c: natural := 4;

  -- One way across the board, command pins and data alike.
  constant flight_c: time := 500 ps;

  constant lane_c: natural := part_c.dq_byte_count;

  subtype word_t is byte_string(0 to lane_c - 1);
  subtype lanes_t is std_ulogic_vector(0 to lane_c - 1);

  type word_vector is array (natural range <>) of word_t;

  -- Payload of a word address, so a read is checked without keeping a
  -- copy of what went in.
  function payload(address: natural) return word_t
  is
    variable ret: word_t;
    variable v: natural := address;
  begin
    for i in 0 to lane_c - 1
    loop
      ret(i) := std_ulogic_vector(to_unsigned((v * 37 + i * 89 + 5) mod 256, 8));
      v := v / 3 + 17;
    end loop;

    return ret;
  end function;

  -- A set bit leaves its lane alone, so this writes the low one only.
  constant low_lane_only_c: lanes_t := "01";

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal cmd_s: cmd_t := cmd_idle;
  signal cmd_ack_s: cmd_ack_t;
  signal wdata_s: wdata_t := wdata_idle;
  signal wdata_ack_s: wdata_ack_t;
  signal rdata_s: rdata_t;
  signal rdata_ack_s: rdata_ack_t := accept(true);
  signal ready_s: std_ulogic;
  signal parity_error_s: std_ulogic;
  signal parity_bad_s: natural := 0;

  -- Controller end of the bus
  signal ram_clock_s: std_ulogic;
  signal ram_cs_n_s: std_ulogic;
  signal ram_cen_n_s: std_ulogic;
  signal ram_we_n_s: std_ulogic;
  signal ram_bw_n_s: lanes_t;
  signal ram_oe_n_s: std_ulogic;
  signal ram_a_s: unsigned(part_c.address_width - 1 downto 0);
  signal ctrl_dq_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal ctrl_dqp_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);

  -- Part end of the bus
  signal part_clock_s: std_ulogic;
  signal part_cs_n_s: std_ulogic;
  signal part_cen_n_s: std_ulogic;
  signal part_we_n_s: std_ulogic;
  signal part_bw_n_s: lanes_t;
  signal part_oe_n_s: std_ulogic;
  signal part_a_s: unsigned(part_c.address_width - 1 downto 0);
  signal model_dq_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal model_dqp_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);

  -- Each end of the data bus sees the far driver a flight later
  signal near_dq_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal far_dq_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal near_dqp_s: std_logic_vector(lane_c - 1 downto 0);
  signal far_dqp_s: std_logic_vector(lane_c - 1 downto 0);

  signal near_dq_value_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal far_dq_value_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal near_dqp_value_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal far_dqp_value_s: std_ulogic_vector(lane_c - 1 downto 0);

  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not stopped_s else '0';
  reset_n_s <= '1' after 3 * tck_c;

  part_clock_s <= transport ram_clock_s after flight_c;
  part_cs_n_s <= transport ram_cs_n_s after flight_c;
  part_cen_n_s <= transport ram_cen_n_s after flight_c;
  part_we_n_s <= transport ram_we_n_s after flight_c;
  part_bw_n_s <= transport ram_bw_n_s after flight_c;
  part_oe_n_s <= transport ram_oe_n_s after flight_c;
  part_a_s <= transport ram_a_s after flight_c;

  dq_wiring: for i in near_dq_s'range
  generate
    near_dq_s(i) <= nsl_io.io.to_logic(ctrl_dq_s(i));
    near_dq_s(i) <= transport nsl_io.io.to_logic(model_dq_s(i)) after flight_c;
    far_dq_s(i) <= transport nsl_io.io.to_logic(ctrl_dq_s(i)) after flight_c;
    far_dq_s(i) <= nsl_io.io.to_logic(model_dq_s(i));
  end generate;

  dqp_wiring: for i in near_dqp_s'range
  generate
    near_dqp_s(i) <= nsl_io.io.to_logic(ctrl_dqp_s(i));
    near_dqp_s(i) <= transport nsl_io.io.to_logic(model_dqp_s(i)) after flight_c;
    far_dqp_s(i) <= transport nsl_io.io.to_logic(ctrl_dqp_s(i)) after flight_c;
    far_dqp_s(i) <= nsl_io.io.to_logic(model_dqp_s(i));
  end generate;

  near_dq_value_s <= std_ulogic_vector(near_dq_s);
  far_dq_value_s <= std_ulogic_vector(far_dq_s);
  near_dqp_value_s <= std_ulogic_vector(near_dqp_s);
  far_dqp_value_s <= std_ulogic_vector(far_dqp_s);

  dut: nsl_ext_ram.sram.sram_controller
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      burst_cycle_count_c => burst_cycle_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,

      ready_o => ready_s,
      parity_error_o => parity_error_s,

      ram_clock_o => ram_clock_s,
      ram_cs_n_o => ram_cs_n_s,
      ram_cen_n_o => ram_cen_n_s,
      ram_we_n_o => ram_we_n_s,
      ram_bw_n_o => ram_bw_n_s,
      ram_oe_n_o => ram_oe_n_s,
      ram_a_o => ram_a_s,
      ram_dq_o => ctrl_dq_s,
      ram_dq_i => near_dq_value_s,
      ram_dqp_o => ctrl_dqp_s,
      ram_dqp_i => near_dqp_value_s
      );

  model: nsl_ext_ram.simulation.sram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => part_clock_s,
      cs_n_i => part_cs_n_s,
      cen_n_i => part_cen_n_s,
      we_n_i => part_we_n_s,
      bw_n_i => part_bw_n_s,
      oe_n_i => part_oe_n_s,
      a_i => part_a_s,
      dq_i => far_dq_value_s,
      dq_o => model_dq_s,
      dqp_i => far_dqp_value_s,
      dqp_o => model_dqp_s,
      violation_count_o => violation_count_s
      );

  -- The ninth bit of each lane has to answer for the eight beside it.
  parity_watch: process is
    variable bad: natural := 0;
  begin
    loop
      wait until rising_edge(clock_s);
      exit when stopped_s;

      if parity_error_s = '1' then
        bad := bad + 1;
        parity_bad_s <= bad;
      end if;
    end loop;

    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 ms;
    assert stopped_s
      report "watchdog fired, the controller is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
    variable errors: natural := 0;
    variable seen: word_t;

    procedure send_command(address: natural; write: boolean) is
    begin
      cmd_s <= cmd_request(to_unsigned(address * lane_c,
                                       max_byte_address_width_c), write);
      loop
        wait until rising_edge(clock_s);
        exit when cmd_ack_s.ready = '1';
      end loop;
      cmd_s <= cmd_idle;
    end procedure;

    procedure send_payload(source: natural; mask: lanes_t) is
    begin
      for beat in 0 to burst_cycle_c - 1
      loop
        wdata_s <= wdata_beat(payload(source + beat), mask);
        loop
          wait until rising_edge(clock_s);
          exit when wdata_ack_s.ready = '1';
        end loop;
      end loop;
      wdata_s <= wdata_idle;
    end procedure;

    procedure collect(address: natural; expect: word_vector) is
    begin
      for beat in 0 to burst_cycle_c - 1
      loop
        loop
          wait until rising_edge(clock_s);
          exit when rdata_s.valid = '1';
        end loop;

        seen := rdata_s.data(0 to lane_c - 1);
        if seen /= expect(beat) then
          errors := errors + 1;
          report "word " & to_string(address + beat) & " answered "
            & to_string(seen) & ", expected " & to_string(expect(beat))
            severity error;
        end if;
      end loop;
    end procedure;

    -- The payload a burst carries need not be the one its own address
    -- stands for: a masked write has to be caught carrying something
    -- else, or dropping the mask would look like success.
    procedure write_burst(address: natural;
                          source: natural := 0;
                          mask: lanes_t := (others => '0')) is
    begin
      send_command(address, true);
      if source = 0 then
        send_payload(address, mask);
      else
        send_payload(source, mask);
      end if;
    end procedure;

    procedure read_burst(address: natural; expect: word_vector) is
    begin
      send_command(address, false);
      collect(address, expect);
    end procedure;

    variable expect: word_vector(0 to burst_cycle_c - 1);
    variable untouched: word_vector(0 to burst_cycle_c - 1);
  begin
    wait until ready_s = '1';
    report "controller ready at " & time'image(now);

    for beat in 0 to burst_cycle_c - 1
    loop
      untouched(beat) := (others => (others => 'U'));
    end loop;

    -- A burst that was never written reads as never written.
    read_burst(16#40#, untouched);

    -- Written, then read back, twice over so the second burst has to
    -- follow the first with the bus already busy.
    for base in 0 to 1
    loop
      write_burst(16#100# + base * burst_cycle_c);
    end loop;

    for base in 0 to 1
    loop
      for beat in 0 to burst_cycle_c - 1
      loop
        expect(beat) := payload(16#100# + base * burst_cycle_c + beat);
      end loop;
      read_burst(16#100# + base * burst_cycle_c, expect);
    end loop;

    -- A burst every lane of which is masked changes nothing, however
    -- different what it carries.
    write_burst(16#100#, source => 16#900#, mask => (others => '1'));
    for beat in 0 to burst_cycle_c - 1
    loop
      expect(beat) := payload(16#100# + beat);
    end loop;
    read_burst(16#100#, expect);

    -- One lane written leaves the other holding what it had.
    write_burst(16#200#);
    write_burst(16#200#, source => 16#900#, mask => low_lane_only_c);
    for beat in 0 to burst_cycle_c - 1
    loop
      expect(beat)(0) := payload(16#900# + beat)(0);
      expect(beat)(1) := payload(16#200# + beat)(1);
    end loop;
    read_burst(16#200#, expect);

    -- Reads and writes following each other with nothing in between
    -- is what the part is for.
    for round in 0 to 3
    loop
      write_burst(16#300# + round * burst_cycle_c);
      for beat in 0 to burst_cycle_c - 1
      loop
        expect(beat) := payload(16#300# + round * burst_cycle_c + beat);
      end loop;
      read_burst(16#300# + round * burst_cycle_c, expect);
    end loop;

    report "controller bench done at " & time'image(now) & ", "
      & to_string(errors) & " mismatches, "
      & to_string(violation_count_s) & " datasheet violations, "
      & to_string(parity_bad_s) & " parity errors";

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    stopped_s <= true;
    -- The count itself is in the report above; the exit status only
    -- has to be non-zero, and a count that is a multiple of 256 would
    -- not be.
    if errors + violation_count_s + parity_bad_s = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
