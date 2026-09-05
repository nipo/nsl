library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_ublox;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_ublox.ubx.all;

entity tb is
end tb;

architecture arch of tb is

  constant clock_period_c : time := 10 ns;
  -- Idle cycles between two bytes, the receiver is fed by a UART.
  constant byte_gap_c : natural := 3;
  -- Cycles the arithmetic is given to settle before a strobe is
  -- called missing, and cycles a discarded frame is watched over.
  constant settle_c : natural := 300;

  constant epoch_offset_c : natural := 315964819;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal byte_s : byte;
  signal valid_s : std_ulogic;

  signal second_a_s, second_b_s : unsigned(31 downto 0);
  signal tacc_a_s, tacc_b_s : unsigned(31 downto 0);
  signal leap_a_s, leap_b_s : signed(7 downto 0);
  signal tow_valid_a_s, week_valid_a_s, leap_valid_a_s : std_ulogic;
  signal tow_valid_b_s, week_valid_b_s, leap_valid_b_s : std_ulogic;
  signal strobe_a_s, strobe_b_s : std_ulogic;

  function ubx_frame(msg_class, msg_id : byte;
                     payload : byte_string) return byte_string
  is
    alias p : byte_string(0 to payload'length-1) is payload;
    variable ret : byte_string(0 to payload'length + 7);
    variable ck_a, ck_b : unsigned(7 downto 0);
  begin
    ret(0) := ubx_sync1_c;
    ret(1) := ubx_sync2_c;
    ret(2) := msg_class;
    ret(3) := msg_id;
    ret(4 to 5) := to_le(to_unsigned(p'length, 16));
    ret(6 to 5 + p'length) := p;

    ck_a := (others => '0');
    ck_b := (others => '0');
    for i in 2 to 5 + p'length
    loop
      ck_a := ck_a + unsigned(ret(i));
      ck_b := ck_b + ck_a;
    end loop;

    ret(6 + p'length) := std_ulogic_vector(ck_a);
    ret(7 + p'length) := std_ulogic_vector(ck_b);
    return ret;
  end function;

  -- Damages one of the two checksum bytes, offset counted back from
  -- the end of the frame.
  function ck_damaged(frame : byte_string;
                      from_end : natural) return byte_string
  is
    alias f : byte_string(0 to frame'length-1) is frame;
    variable ret : byte_string(0 to frame'length-1);
  begin
    ret := f;
    ret(f'length-1 - from_end) := f(f'length-1 - from_end) xor x"ff";
    return ret;
  end function;

  function timegps_payload(itow_ms : natural;
                           week : natural;
                           leap : integer;
                           valid : natural;
                           tacc : natural;
                           payload_length : natural := ubx_nav_timegps_length_c)
    return byte_string
  is
    variable ret : byte_string(0 to payload_length-1);
  begin
    ret := (others => to_byte(0));
    ret(ubx_timegps_off_itow_c to ubx_timegps_off_itow_c + 3)
      := to_le(to_unsigned(itow_ms, 32));
    ret(ubx_timegps_off_week_c to ubx_timegps_off_week_c + 1)
      := to_le(to_unsigned(week, 16));
    ret(ubx_timegps_off_leap_c) := std_ulogic_vector(to_signed(leap, 8));
    ret(ubx_timegps_off_valid_c) := to_byte(valid);
    ret(ubx_timegps_off_tacc_c to ubx_timegps_off_tacc_c + 3)
      := to_le(to_unsigned(tacc, 32));
    return ret;
  end function;

  function timegps_frame(itow_ms : natural;
                         week : natural;
                         leap : integer;
                         valid : natural;
                         tacc : natural;
                         payload_length : natural := ubx_nav_timegps_length_c)
    return byte_string
  is
  begin
    return ubx_frame(ubx_class_nav_c, ubx_id_nav_timegps_c,
                     timegps_payload(itow_ms, week, leap, valid, tacc,
                                     payload_length));
  end function;

  function gps_second(week : natural; itow_ms : natural) return natural
  is
  begin
    return week * gps_week_seconds_c + itow_ms / 1000;
  end function;

  -- Eight bytes of line noise that cannot be mistaken for a frame
  -- start, long enough to flush any partial header the framer picked
  -- up from a damaged frame.
  constant flush_c : byte_string := to_byte_string("XXXXXXXX");

  constant lone_sync_c : byte_string(0 to 0) := (others => ubx_sync1_c);

begin

  stim: process is
    constant ctxt : log_context := "timegps";

    procedure send(data : byte_string) is
    begin
      for i in data'range
      loop
        wait until falling_edge(clock_s);
        byte_s <= data(i);
        valid_s <= '1';
        wait until falling_edge(clock_s);
        valid_s <= '0';
        byte_s <= to_byte(0);
        for j in 1 to byte_gap_c
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;
    end procedure;

    procedure expect_frame(what : string;
                           week : natural;
                           itow_ms : natural;
                           leap : integer;
                           valid : natural;
                           tacc : natural) is
      variable base : natural;
      variable waited : natural;
      variable flags : byte;
    begin
      base := gps_second(week, itow_ms);
      flags := to_byte(valid);
      waited := 0;
      loop
        wait until rising_edge(clock_s);
        exit when strobe_a_s = '1';
        assert waited < settle_c
          report what & ": no strobe for the accepted frame"
          severity failure;
        waited := waited + 1;
      end loop;

      assert_equal(ctxt, what & " strobe of the offset instance",
                   strobe_b_s, '1', failure);
      assert_equal(ctxt, what & " second",
                   second_a_s, to_unsigned(base, 32), failure);
      assert_equal(ctxt, what & " second with epoch offset",
                   second_b_s, to_unsigned(base + epoch_offset_c, 32),
                   failure);
      assert_equal(ctxt, what & " leap",
                   std_ulogic_vector(leap_a_s),
                   std_ulogic_vector(to_signed(leap, 8)), failure);
      assert_equal(ctxt, what & " tacc",
                   tacc_a_s, to_unsigned(tacc, 32), failure);
      assert_equal(ctxt, what & " tow valid",
                   tow_valid_a_s, flags(0), failure);
      assert_equal(ctxt, what & " week valid",
                   week_valid_a_s, flags(1), failure);
      assert_equal(ctxt, what & " leap valid",
                   leap_valid_a_s, flags(2), failure);

      wait until rising_edge(clock_s);
      assert_equal(ctxt, what & " strobe is one cycle long",
                   strobe_a_s, '0', failure);
    end procedure;

    -- Watches the whole settling window of a frame that must be
    -- discarded, and checks the held outputs did not move.
    procedure expect_discarded(what : string;
                               week : natural;
                               itow_ms : natural) is
      variable base : natural;
    begin
      base := gps_second(week, itow_ms);
      for i in 1 to settle_c
      loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, what & " strobe", strobe_a_s, '0', failure);
      end loop;

      assert_equal(ctxt, what & " second held",
                   second_a_s, to_unsigned(base, 32), failure);
      assert_equal(ctxt, what & " second with epoch offset held",
                   second_b_s, to_unsigned(base + epoch_offset_c, 32),
                   failure);
    end procedure;

  begin
    done_s <= (others => '0');
    valid_s <= '0';
    byte_s <= to_byte(0);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    log_info(ctxt, "clean NAV-TIMEGPS");
    send(timegps_frame(259199999, 2400, 18, 16#07#, 25));
    expect_frame("clean", 2400, 259199999, 18, 16#07#, 25);

    log_info(ctxt, "foreign frames interleaved");
    send(ubx_frame(ubx_class_nav_c, to_byte(16#07#),
                   (0 to 91 => to_byte(16#5a#))));
    send(ubx_frame(to_byte(16#05#), to_byte(16#01#),
                   (to_byte(16#01#), to_byte(16#20#))));
    send(timegps_frame(1000, 1024, 17, 16#03#, 100));
    expect_frame("after foreign", 1024, 1000, 17, 16#03#, 100);

    log_info(ctxt, "line garbage and resync");
    send(to_byte_string("$GPGGA,123519,4807.038,N,01131.000,E*47"));
    send(lone_sync_c);
    send(to_byte_string("$GPRMC,123519,A,4807.038,N*6A"));
    -- Stray sync1 glued to the frame's own sync1: the hunt must stay
    -- armed rather than take the second one for sync2.
    send(lone_sync_c & timegps_frame(999, 2048, 18, 16#07#, 7));
    expect_frame("after garbage", 2048, 999, 18, 16#07#, 7);

    log_info(ctxt, "damaged checksum");
    send(ck_damaged(timegps_frame(1234567, 1000, 15, 16#07#, 3), 1));
    send(flush_c);
    expect_discarded("damaged ck_a", 2048, 999);
    send(ck_damaged(timegps_frame(1234567, 1000, 15, 16#07#, 3), 0));
    send(flush_c);
    expect_discarded("damaged ck_b", 2048, 999);

    send(timegps_frame(604799999, 2047, 18, 16#07#, 42));
    expect_frame("after damage", 2047, 604799999, 18, 16#07#, 42);

    log_info(ctxt, "wrong length for the class and id");
    send(timegps_frame(1234567, 1000, 15, 16#07#, 3, 20));
    expect_discarded("wrong length", 2047, 604799999);

    send(timegps_frame(1999, 1023, -1, 16#01#, 3));
    expect_frame("after wrong length", 1023, 1999, -1, 16#01#, 3);

    log_info(ctxt, "done");
    done_s <= (others => '1');
    wait;
  end process;

  dut_a: nsl_ublox.ubx.ubx_nav_timegps
    generic map(
      epoch_offset_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      byte_i => byte_s,
      valid_i => valid_s,
      second_o => second_a_s,
      leap_s_o => leap_a_s,
      tow_valid_o => tow_valid_a_s,
      week_valid_o => week_valid_a_s,
      leap_valid_o => leap_valid_a_s,
      tacc_o => tacc_a_s,
      strobe_o => strobe_a_s
      );

  dut_b: nsl_ublox.ubx.ubx_nav_timegps
    generic map(
      epoch_offset_c => epoch_offset_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      byte_i => byte_s,
      valid_i => valid_s,
      second_o => second_b_s,
      leap_s_o => leap_b_s,
      tow_valid_o => tow_valid_b_s,
      week_valid_o => week_valid_b_s,
      leap_valid_o => leap_valid_b_s,
      tacc_o => tacc_b_s,
      strobe_o => strobe_b_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 3,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
