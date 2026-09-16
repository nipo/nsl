library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_usb.io.all;
use nsl_usb.usb.all;
use nsl_usb.ls_bfm.all;
use nsl_usb.hid_host.all;
use nsl_usb.hid_program.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;

-- The same host talking to a full-speed device.
--
-- What is full speed about a bus is that bits are eight times shorter
-- and that J is the other line.  Neither is a property of the device
-- model, so the low-speed one serves here unchanged, with two things
-- done to it instead:
--
-- * The two lines are crossed between the host and the device.  The
--   host, once it has decided it is talking to a full-speed device,
--   swaps them itself; crossing them back makes a device speaking
--   the low-speed sense of the lines into a full-speed device on the
--   wire, which is what the host now has to cope with.
--
-- * The host is clocked at an eighth of what it is told it runs at. A
--   full-speed bit is clock_rate_c/12MHz cycles, four at the 48MHz
--   stated here, so at 6MHz a full-speed bit lasts exactly as long as
--   the low-speed bit the device model sends.  Nothing in the host
--   measures anything in seconds that this test looks at, so slowing
--   everything down equally changes nothing but how long the run
--   takes to watch.
--
-- Which leaves the things that really are new: that the host works
-- out the speed from the line the device pulls up, that it then keeps
-- four-cycle bit timing rather than thirty two, and that it sends
-- start-of-frame tokens where a low-speed host would send bare end of
-- packets.  A malformed one of those would leave the device model
-- unable to follow the bus at all, so enumerating at all is the check.
entity host_test is
  generic(ep0_mps_c: positive);
  port(done_o: out std_ulogic);
end entity;

architecture beh of host_test is

  constant device_descriptor_c: byte_string
    := from_hex("12010001000000") & std_ulogic_vector(to_unsigned(ep0_mps_c, 8))
       & from_hex("21436587000100000001");

  constant config_descriptor_c: byte_string := from_hex(
    "090240000101008032"
    & "090400000103010100"
    & "092111010001223f00"
    & "0705810308000a"
    & "1e24") & byte_string'(0 to 27 => x"ff");

  constant report_a_c: byte_string(0 to 7) := from_hex("0000040506000000");
  constant report_b_c: byte_string(0 to 7) := from_hex("0200070000000000");

  constant poll_interval_ms_c: natural := 2;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;

  -- The bus as the host drives and sees it
  signal host_c_s: usb_io_c;
  signal host_s_s: usb_io_s;
  -- And as the device does, the two lines crossed on the way
  signal device_c_s: usb_io_c;
  signal device_s_s: usb_io_s;

  signal identity_s: device_identity_t;
  signal status_s: hid_host_status_t;
  signal report_s: nsl_amba.axi4_stream.bus_t;

  signal present_s: std_ulogic := '1';
  signal report_data_s: byte_string(0 to 7) := (others => x"00");
  signal report_length_s: natural range 0 to 8 := 0;
  signal report_valid_s: std_ulogic := '0';
  signal report_ready_s: std_ulogic;

  -- The bus as a listener sees it: what the host drives while it is
  -- driving, idle otherwise.
  signal snoop_s: usb_io_s;
  signal sof_count_s: natural := 0;

  signal frame_s: byte_string(0 to 7) := (others => x"00");
  signal frame_len_s: natural := 0;
  signal frame_count_s: natural := 0;

begin

  -- 6MHz: see above.
  clock_gen: process is
  begin
    clock_s <= '0';
    wait for 83334 ps;
    clock_s <= '1';
    wait for 83333 ps;
  end process;

  reset_n_s <= '0', '1' after 500 ns;

  dut: nsl_usb.hid_host.hid_host_engine
    generic map(
      program_c => hid_program(hid_program_config_t'(
        poll_interval_ms => poll_interval_ms_c,
        report_length => 8,
        configuration_value => 1,
        -- Nothing here is testing how long a contact bounces.
        debounce_ms => 4)),
      clock_rate_c => 48_000_000,
      full_speed_c => true
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      bus_o => host_c_s,
      bus_i => host_s_s,
      identity_o => identity_s,
      status_o => status_s,
      report_o => report_s.m,
      report_i => report_s.s
      );

  -- The crossing that makes this a full-speed bus.
  device_c_s.dp <= host_c_s.dm;
  device_c_s.dm <= host_c_s.dp;
  device_c_s.oe <= host_c_s.oe;
  device_c_s.dp_pullup_en <= host_c_s.dp_pullup_en;

  host_s_s.dp <= device_s_s.dm;
  host_s_s.dm <= device_s_s.dp;

  device: nsl_usb.ls_bfm.ls_device_bfm
    generic map(
      device_descriptor_c => device_descriptor_c,
      config_descriptor_c => config_descriptor_c,
      interrupt_ep_c => 1,
      ep0_mps_c => ep0_mps_c,
      control_nak_count_c => 2,
      control_silent_count_c => 1,
      control_bad_crc_once_c => true
      )
    port map(
      host_i => device_c_s,
      host_o => device_s_s,
      present_i => present_s,
      report_data_i => report_data_s,
      report_length_i => report_length_s,
      report_valid_i => report_valid_s,
      report_ready_o => report_ready_s
      );

  report_s.s <= accept(report_cfg_c, true);

  collector: process is
    variable buf: byte_string(0 to 7) := (others => x"00");
    variable count: natural := 0;
  begin
    wait until rising_edge(clock_s);

    if is_valid(report_cfg_c, report_s.m) then
      if count < buf'length then
        buf(count) := bytes(report_cfg_c, report_s.m)(0);
      end if;
      count := count + 1;

      if is_last(report_cfg_c, report_s.m) then
        frame_s <= buf;
        frame_len_s <= count;
        frame_count_s <= frame_count_s + 1;
        buf := (others => x"00");
        count := 0;
      end if;
    end if;
  end process;

  snoop_s.dp <= device_c_s.dp when device_c_s.oe = '1' else '0';
  snoop_s.dm <= device_c_s.dm when device_c_s.oe = '1' else '1';

  -- Every start-of-frame token the host sends, against what one for
  -- that frame number should carry.  The device model has no use for
  -- them and says so, which leaves nothing else checking that the
  -- frame number counts or that its CRC5 is right -- and a host whose
  -- SOF is malformed is one some devices will refuse to talk to.
  sof_check: process is
    variable rx: byte_string(0 to 71);
    variable len: natural;
    variable frame: frame_no_t := (others => '0');
  begin
    loop
      if snoop_s.dm = '1' then
        wait until snoop_s.dm = '0';
      end if;

      if snoop_s.dp /= '1' then
        -- Single-ended zero: a packet ending rather than one starting
        wait until snoop_s.dm = '1';
      else
        ls_packet_decode(snoop_s, rx, len);

        if len = 3 and rx(0) = pid_byte(PID_SOF) then
          assert rx(1 to 2) = sof_data(frame)
            report "Start of frame " & to_string(to_integer(frame))
            & " carried " & to_hex_string(rx(1 to 2)) & " where "
            & to_hex_string(sof_data(frame)) & " was due"
            severity failure;

          frame := frame + 1;
          sof_count_s <= sof_count_s + 1;
        end if;
      end if;
    end loop;
  end process;

  watchdog_check: process is
  begin
    wait until rising_edge(clock_s);

    assert status_s.error = '0'
      report "Protocol watchdog fired"
      severity failure;
  end process;

  stim: process is
    variable seen: natural;
  begin
    done_o <= '0';
    log_info("* Enumeration of a full-speed device");

    wait until identity_s.valid for 4 sec;
    assert identity_s.valid
      report "Device did not enumerate"
      severity failure;

    assert identity_s.vid = x"4321" and identity_s.pid = x"8765"
      report "Identity came back as "
      & to_hex_string(std_ulogic_vector(identity_s.vid)) & ":"
      & to_hex_string(std_ulogic_vector(identity_s.pid))
      severity failure;

    assert identity_s.if_class = x"03" and identity_s.if_protocol = x"01"
      report "Interface came back as class "
      & to_hex_string(identity_s.if_class) & " protocol "
      & to_hex_string(identity_s.if_protocol)
      severity failure;

    log_info("* Reports");

    for i in 0 to 1
    loop
      seen := frame_count_s;

      wait until falling_edge(clock_s);
      if i = 0 then
        report_data_s <= report_a_c;
      else
        report_data_s <= report_b_c;
      end if;
      report_length_s <= 8;
      report_valid_s <= '1';

      wait until frame_count_s /= seen for 200 ms;
      assert frame_count_s /= seen
        report "Report " & to_string(i) & " never arrived"
        severity failure;

      wait until falling_edge(clock_s);
      report_valid_s <= '0';

      assert frame_len_s = 8
        report "Report " & to_string(i) & " came back " & to_string(frame_len_s)
        & " bytes long"
        severity failure;

      if i = 0 then
        assert frame_s = report_a_c
          report "Report " & to_string(i) & " came back as "
          & to_hex_string(frame_s)
          severity failure;
      else
        assert frame_s = report_b_c
          report "Report " & to_string(i) & " came back as "
          & to_hex_string(frame_s)
          severity failure;
      end if;
    end loop;

    -- One a millisecond since the bus reset, so by now there are many.
    assert sof_count_s > 20
      report "Only " & to_string(sof_count_s)
      & " start-of-frame tokens went by"
      severity failure;

    log_info("* Done, EP0 MPS " & to_string(ep0_mps_c));
    done_o <= '1';
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
library nsl_simulation;

entity tb is
end entity;

architecture beh of tb is
  signal done_s: std_ulogic_vector(0 to 3);
begin
  sizes: for i in 0 to 3 generate
    test: entity work.host_test
      generic map(ep0_mps_c => 8 * 2**i)
      port map(done_o => done_s(i));
  end generate;

  finish: process is
  begin
    wait until done_s = "1111";
    nsl_simulation.control.terminate(0);
    wait;
  end process;
end architecture;
