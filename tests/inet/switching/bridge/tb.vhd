library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_inet.ethernet.all;
use nsl_inet.switching.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- System-level exercise of one switching_bridge instance.  The entity
-- plays the MACs attached to every port: a driver injects frames on
-- request, a monitor accepts everything the bridge sends, keeps a
-- per-port frame counter and the last frame received on the port.
--
-- Scenario boundaries compare the whole counter vector, so a frame
-- reaching a port that should have stayed silent fails the run just as
-- a missing frame does.
entity bridge_test is
  generic(
    name_c: string;
    byte_count_c: natural range 1 to 4;
    learning_c: boolean;
    -- 0: learning bridge, full scenario list
    -- 1: learning bridge, flood then learned unicast
    -- 2: static table
    mode_c: natural;
    static_macs_c: mac48_vector := no_static_macs_c;
    static_ports_c: port_index_vector := no_static_ports_c
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out std_ulogic
    );
end entity;

architecture beh of bridge_test is

  constant port_count_c: natural := 4;
  constant max_len_c: natural := 80;

  -- Hosts.  A and A' sit on port 0, B on port 1, C on port 2, D on
  -- port 3.  E and X are never learned by the scenarios that use them.
  constant mac_a_c: mac48_t := from_hex("02000000000a");
  constant mac_ap_c: mac48_t := from_hex("02000000001a");
  constant mac_b_c: mac48_t := from_hex("02000000000b");
  constant mac_c_c: mac48_t := from_hex("02000000000c");
  constant mac_d_c: mac48_t := from_hex("02000000000d");
  constant mac_e_c: mac48_t := from_hex("02000000000e");
  constant mac_x_c: mac48_t := from_hex("0200000000cc");

  constant cfg_c: nsl_inet.switching.config_t
    := nsl_inet.switching.config(byte_count => byte_count_c,
                                 port_count => port_count_c,
                                 buffer_bytes_l2 => 11,
                                 learning_enabled => learning_c);

  constant pcfg_c: nsl_amba.axi4_stream.config_t := port_config(cfg_c);

  -- Egress ports that alternate ready, so that fabric backpressure is
  -- exercised through the top level.
  constant stall_c: std_ulogic_vector(0 to port_count_c-1) := "0101";

  type frame_t is
  record
    data: byte_string(0 to max_len_c-1);
    length: natural;
    bad: boolean;
  end record;

  type frame_vector is array(natural range <>) of frame_t;
  type natural_vector is array(natural range <>) of natural;
  subtype port_natural_vector is natural_vector(0 to port_count_c-1);

  function make_frame(da, sa: mac48_t;
                      length: natural;
                      tag: natural;
                      bad: boolean := false) return frame_t
  is
    variable ret: frame_t;
  begin
    ret.data := (others => x"00");
    ret.data(0 to 5) := da;
    ret.data(6 to 11) := sa;
    for i in 12 to length-1
    loop
      ret.data(i) := byte(to_unsigned((i * 13 + tag * 31) mod 256, 8));
    end loop;
    ret.length := length;
    ret.bad := bad;
    return ret;
  end function;

  function flood_all return port_mask_t
  is
    variable ret: port_mask_t := (others => '1');
  begin
    return ret;
  end function;

  function flood_but_3 return port_mask_t
  is
    variable ret: port_mask_t := (others => '1');
  begin
    ret(3) := '0';
    return ret;
  end function;

  signal in_m_s: nsl_amba.axi4_stream.master_vector(0 to port_count_c-1);
  signal in_s_s: nsl_amba.axi4_stream.slave_vector(0 to port_count_c-1);
  signal out_m_s: nsl_amba.axi4_stream.master_vector(0 to port_count_c-1);
  signal out_s_s: nsl_amba.axi4_stream.slave_vector(0 to port_count_c-1);
  signal flood_s: port_mask_t;

  signal inject_data_s: frame_vector(0 to port_count_c-1);
  signal inject_req_s, inject_ack_s: std_ulogic_vector(0 to port_count_c-1);

  signal rx_count_s: port_natural_vector;
  signal rx_frame_s: frame_vector(0 to port_count_c-1);

begin

  dut: nsl_inet.switching.switching_bridge
    generic map(
      config_c => cfg_c,
      static_macs_c => static_macs_c,
      static_ports_c => static_ports_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flood_mask_i => flood_s,

      in_i => in_m_s,
      in_o => in_s_s,

      out_o => out_m_s,
      out_i => out_s_s
      );

  ports: for p in 0 to port_count_c-1 generate

    -- Frame injector.  The bridge ingress may never backpressure, so
    -- beats go out one per cycle.
    driver: process is
      variable f_v: frame_t;
      variable offset_v, count_v: natural;
      variable data_v: byte_string(0 to byte_count_c-1);
      variable keep_v: std_ulogic_vector(0 to byte_count_c-1);
      variable user_v: std_ulogic_vector(0 downto 0);
      variable last_v: boolean;
    begin
      in_m_s(p) <= transfer_defaults(pcfg_c);
      inject_ack_s(p) <= '0';

      wait until reset_n_i = '1';

      loop
        wait until falling_edge(clock_i);
        next when inject_req_s(p) = '0';

        f_v := inject_data_s(p);
        offset_v := 0;

        while offset_v < f_v.length
        loop
          count_v := f_v.length - offset_v;
          if count_v > byte_count_c then
            count_v := byte_count_c;
          end if;
          last_v := offset_v + count_v >= f_v.length;

          data_v := (others => x"00");
          keep_v := (others => '0');
          for i in 0 to count_v-1
          loop
            data_v(i) := f_v.data(offset_v + i);
            keep_v(i) := '1';
          end loop;

          if last_v and f_v.bad then
            user_v := "1";
          else
            user_v := "0";
          end if;

          in_m_s(p) <= transfer(pcfg_c,
                                bytes => data_v,
                                keep => keep_v,
                                user => user_v,
                                last => last_v);

          wait until rising_edge(clock_i);
          assert is_ready(pcfg_c, in_s_s(p))
            report name_c&": ingress "&to_string(p)&" backpressured the MAC"
            severity failure;
          wait until falling_edge(clock_i);

          offset_v := offset_v + count_v;
        end loop;

        in_m_s(p) <= transfer_defaults(pcfg_c);
        inject_ack_s(p) <= '1';

        while inject_req_s(p) = '1'
        loop
          wait until falling_edge(clock_i);
        end loop;

        inject_ack_s(p) <= '0';
      end loop;
    end process;

    -- Egress monitor.  Reassembles frames, checks beat packing, and
    -- publishes a running frame count with the last frame seen.
    monitor: process is
      variable buffer_v: byte_string(0 to max_len_c-1);
      variable data_v: byte_string(0 to byte_count_c-1);
      variable length_v, count_v, total_v: natural;
      variable ready_v: boolean;
    begin
      out_s_s(p) <= accept(pcfg_c, false);
      rx_count_s(p) <= 0;
      rx_frame_s(p).length <= 0;
      rx_frame_s(p).data <= (others => x"00");
      rx_frame_s(p).bad <= false;
      buffer_v := (others => x"00");
      length_v := 0;
      total_v := 0;
      ready_v := true;

      wait until reset_n_i = '1';

      loop
        if stall_c(p) = '1' then
          ready_v := not ready_v;
        end if;
        out_s_s(p) <= accept(pcfg_c, ready_v);

        wait until rising_edge(clock_i);

        if ready_v and is_valid(pcfg_c, out_m_s(p)) then
          count_v := byte_count(pcfg_c, out_m_s(p));
          data_v := bytes(pcfg_c, out_m_s(p));

          assert length_v + count_v <= max_len_c
            report name_c&": egress "&to_string(p)&" frame is too long"
            severity failure;

          for i in 0 to count_v-1
          loop
            buffer_v(length_v + i) := data_v(i);
          end loop;
          length_v := length_v + count_v;

          if is_last(pcfg_c, out_m_s(p)) then
            assert user(pcfg_c, out_m_s(p))(0) = '0'
              report name_c&": egress "&to_string(p)&" flagged a bad frame"
              severity failure;

            total_v := total_v + 1;
            rx_frame_s(p).data <= buffer_v;
            rx_frame_s(p).length <= length_v;
            rx_count_s(p) <= total_v;
            length_v := 0;
          else
            assert count_v = byte_count_c
              report name_c&": egress "&to_string(p)
              &" left holes in a non-last beat"
              severity failure;
          end if;
        end if;

        wait until falling_edge(clock_i);
      end loop;
    end process;

  end generate;

  stim: process is

    procedure idle(constant cycles: natural) is
    begin
      for i in 1 to cycles
      loop
        wait until falling_edge(clock_i);
      end loop;
    end procedure;

    procedure inject_start(constant p: natural;
                           constant f: frame_t) is
    begin
      inject_data_s(p) <= f;
      inject_req_s(p) <= '1';
    end procedure;

    procedure inject_wait(constant p: natural) is
    begin
      while inject_ack_s(p) = '0'
      loop
        wait until falling_edge(clock_i);
      end loop;

      inject_req_s(p) <= '0';

      while inject_ack_s(p) = '1'
      loop
        wait until falling_edge(clock_i);
      end loop;
    end procedure;

    procedure send(constant p: natural;
                   constant f: frame_t) is
    begin
      inject_start(p, f);
      inject_wait(p);
    end procedure;

    -- Waits for the expected per-port frame counts, then leaves the
    -- switch idle long enough for any extra copy to show up, and
    -- checks the counts again.
    procedure settle(constant what: string;
                     constant expect: port_natural_vector) is
      variable guard_v: natural;
    begin
      guard_v := 0;
      while rx_count_s /= expect
      loop
        for p in 0 to port_count_c-1
        loop
          assert rx_count_s(p) <= expect(p)
            report name_c&": "&what&": egress "&to_string(p)
            &" received an unexpected frame"
            severity failure;
        end loop;

        wait until falling_edge(clock_i);
        guard_v := guard_v + 1;
        assert guard_v < 20000
          report name_c&": "&what&": frames never arrived"
          severity failure;
      end loop;

      idle(200);

      for p in 0 to port_count_c-1
      loop
        assert_equal(name_c&": "&what&": egress "&to_string(p)&" frame count",
                     rx_count_s(p), expect(p), FAILURE);
      end loop;
    end procedure;

    procedure check_frame(constant what: string;
                          constant p: natural;
                          constant f: frame_t) is
    begin
      assert_equal(name_c&": "&what&": egress "&to_string(p)&" frame length",
                   rx_frame_s(p).length, f.length, FAILURE);
      assert_equal(name_c&": "&what&": egress "&to_string(p)&" frame data",
                   rx_frame_s(p).data(0 to f.length-1),
                   f.data(0 to f.length-1), FAILURE);
    end procedure;

    variable e_v: port_natural_vector;
    variable f_v: frame_t;

  begin
    done_o <= '0';
    inject_req_s <= (others => '0');
    for p in 0 to port_count_c-1
    loop
      inject_data_s(p) <= make_frame(mac_a_c, mac_b_c, 14, 0);
    end loop;
    flood_s <= flood_all;

    wait until reset_n_i = '1';
    idle(8);

    e_v := (others => 0);

    case mode_c is
      when 0 =>
        -- Unknown unicast from A on port 0 is flooded everywhere but
        -- back to port 0.
        log_info(name_c, "unknown unicast floods");
        f_v := make_frame(mac_b_c, mac_a_c, 60, 1);
        send(0, f_v);
        e_v := (0, 1, 1, 1);
        settle("unknown unicast", e_v);
        check_frame("unknown unicast", 1, f_v);
        check_frame("unknown unicast", 2, f_v);
        check_frame("unknown unicast", 3, f_v);

        -- A was learned on port 0, so B's reply only reaches port 0.
        log_info(name_c, "reply to a learned address");
        f_v := make_frame(mac_a_c, mac_b_c, 61, 2);
        send(1, f_v);
        e_v := (1, 1, 1, 1);
        settle("reply", e_v);
        check_frame("reply", 0, f_v);

        -- B was learned on port 1 by the reply.
        log_info(name_c, "learned unicast");
        f_v := make_frame(mac_b_c, mac_a_c, 62, 3);
        send(0, f_v);
        e_v := (1, 2, 1, 1);
        settle("learned unicast", e_v);
        check_frame("learned unicast", 1, f_v);

        -- Broadcast reaches every port but its own.
        log_info(name_c, "broadcast");
        f_v := make_frame(ethernet_broadcast_addr_c, mac_c_c, 63, 4);
        send(2, f_v);
        e_v := (2, 3, 1, 2);
        settle("broadcast", e_v);
        check_frame("broadcast", 0, f_v);
        check_frame("broadcast", 1, f_v);
        check_frame("broadcast", 3, f_v);

        -- A' announces itself on port 0...
        log_info(name_c, "destination on the ingress port");
        f_v := make_frame(mac_b_c, mac_ap_c, 60, 5);
        send(0, f_v);
        e_v := (2, 4, 1, 2);
        settle("learning A'", e_v);
        check_frame("learning A'", 1, f_v);

        -- ... so a port-0 frame addressed to A' is dropped silently.
        f_v := make_frame(mac_ap_c, mac_a_c, 60, 6);
        send(0, f_v);
        settle("hit on ingress port", e_v);

        -- Traffic after the drop is unaffected.
        f_v := make_frame(mac_b_c, mac_a_c, 64, 7);
        send(0, f_v);
        e_v := (2, 5, 1, 2);
        settle("after ingress-port drop", e_v);
        check_frame("after ingress-port drop", 1, f_v);

        -- A frame flagged bad on its last beat is dropped whole...
        log_info(name_c, "bad frame");
        f_v := make_frame(mac_a_c, mac_e_c, 60, 8, bad => true);
        send(3, f_v);
        settle("bad frame", e_v);

        -- ... and its source address was not learned.
        f_v := make_frame(mac_e_c, mac_b_c, 61, 9);
        send(1, f_v);
        e_v := (3, 5, 2, 3);
        settle("address of a bad frame", e_v);
        check_frame("address of a bad frame", 0, f_v);
        check_frame("address of a bad frame", 2, f_v);
        check_frame("address of a bad frame", 3, f_v);

        -- D announces itself on port 3.
        log_info(name_c, "restricted flood mask");
        f_v := make_frame(mac_a_c, mac_d_c, 62, 10);
        send(3, f_v);
        e_v := (4, 5, 2, 3);
        settle("learning D", e_v);
        check_frame("learning D", 0, f_v);

        -- Port 3 is out of the flood set, so it misses a broadcast...
        flood_s <= flood_but_3;
        idle(4);
        f_v := make_frame(ethernet_broadcast_addr_c, mac_c_c, 63, 11);
        send(2, f_v);
        e_v := (5, 6, 2, 3);
        settle("masked broadcast", e_v);
        check_frame("masked broadcast", 0, f_v);
        check_frame("masked broadcast", 1, f_v);

        -- ... but still receives what is addressed to it.
        f_v := make_frame(mac_d_c, mac_c_c, 64, 12);
        send(2, f_v);
        e_v := (5, 6, 2, 4);
        settle("masked port, learned unicast", e_v);
        check_frame("masked port, learned unicast", 3, f_v);

        flood_s <= flood_all;
        idle(4);

        -- Two learned unicast frames crossing the fabric at once.
        log_info(name_c, "cross traffic");
        f_v := make_frame(mac_b_c, mac_a_c, 65, 13);
        inject_start(0, f_v);
        inject_start(2, make_frame(mac_d_c, mac_c_c, 66, 14));
        inject_wait(0);
        inject_wait(2);
        e_v := (5, 7, 2, 5);
        settle("cross traffic", e_v);
        check_frame("cross traffic", 1, f_v);
        check_frame("cross traffic", 3, make_frame(mac_d_c, mac_c_c, 66, 14));

      when 1 =>
        -- Width-generic smoke test: one flood, one learned unicast.
        log_info(name_c, "unknown unicast floods");
        f_v := make_frame(mac_b_c, mac_a_c, 60, 1);
        send(0, f_v);
        e_v := (0, 1, 1, 1);
        settle("unknown unicast", e_v);
        check_frame("unknown unicast", 1, f_v);
        check_frame("unknown unicast", 2, f_v);
        check_frame("unknown unicast", 3, f_v);

        f_v := make_frame(mac_a_c, mac_b_c, 61, 2);
        send(1, f_v);
        e_v := (1, 1, 1, 1);
        settle("reply", e_v);
        check_frame("reply", 0, f_v);

        log_info(name_c, "learned unicast");
        f_v := make_frame(mac_b_c, mac_a_c, 62, 3);
        send(0, f_v);
        e_v := (1, 2, 1, 1);
        settle("learned unicast", e_v);
        check_frame("learned unicast", 1, f_v);

      when 2 =>
        -- Static table: B on port 1, D on port 3, A on port 0.
        log_info(name_c, "listed destination");
        f_v := make_frame(mac_b_c, mac_a_c, 60, 1);
        send(0, f_v);
        e_v := (0, 1, 0, 0);
        settle("listed destination", e_v);
        check_frame("listed destination", 1, f_v);

        -- An address that is not listed is flooded, and its source is
        -- not remembered.
        log_info(name_c, "unlisted destination floods");
        f_v := make_frame(mac_x_c, mac_c_c, 61, 2);
        send(2, f_v);
        e_v := (1, 2, 0, 1);
        settle("unlisted destination", e_v);
        check_frame("unlisted destination", 0, f_v);
        check_frame("unlisted destination", 1, f_v);
        check_frame("unlisted destination", 3, f_v);

        f_v := make_frame(mac_x_c, mac_a_c, 62, 3);
        send(0, f_v);
        e_v := (1, 3, 1, 2);
        settle("no learning happened", e_v);
        check_frame("no learning happened", 1, f_v);
        check_frame("no learning happened", 2, f_v);
        check_frame("no learning happened", 3, f_v);

        log_info(name_c, "second listed destination");
        f_v := make_frame(mac_d_c, mac_c_c, 63, 4);
        send(2, f_v);
        e_v := (1, 3, 1, 3);
        settle("second listed destination", e_v);
        check_frame("second listed destination", 3, f_v);

        -- A is listed on port 0, which is where the frame comes from.
        log_info(name_c, "listed on the ingress port");
        f_v := make_frame(mac_a_c, mac_ap_c, 60, 5);
        send(0, f_v);
        settle("listed on the ingress port", e_v);

      when others =>
        assert false
          report name_c&": unknown scenario mode"
          severity failure;
    end case;

    log_info(name_c, "all scenarios passed");

    done_o <= '1';
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_inet, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_inet.ethernet.all;
use nsl_inet.switching.all;

entity tb is
end tb;

architecture arch of tb is

  -- Static lists carry their bounds into the generics they are mapped
  -- to, so they must be constrained explicitly here.
  constant static_macs_c: mac48_vector(0 to 2) := (from_hex("02000000000b"),
                                                   from_hex("02000000000d"),
                                                   from_hex("02000000000a"));
  constant static_ports_c: port_index_vector(0 to 2) := (1, 3, 0);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

begin

  learning: entity work.bridge_test
    generic map(
      name_c => "bridge 1B",
      byte_count_c => 1,
      learning_c => true,
      mode_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  wide: entity work.bridge_test
    generic map(
      name_c => "bridge 4B",
      byte_count_c => 4,
      learning_c => true,
      mode_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  static: entity work.bridge_test
    generic map(
      name_c => "bridge static",
      byte_count_c => 1,
      learning_c => false,
      mode_c => 2,
      static_macs_c => static_macs_c,
      static_ports_c => static_ports_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
