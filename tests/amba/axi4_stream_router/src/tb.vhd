library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  constant in_count_c : natural := 3;
  constant out_count_c : natural := 2;
  constant in_header_length_c : natural := 2;
  constant out_header_length_c : natural := 3;

  signal in_s: master_vector(0 to in_count_c-1);
  signal in_ack_s: slave_vector(0 to in_count_c-1);
  signal out_s: master_vector(0 to out_count_c-1);
  signal out_ack_s: slave_vector(0 to out_count_c-1);

  signal route_valid_s : std_ulogic;
  signal route_header_s : byte_string(0 to in_header_length_c-1);
  signal route_source_s : natural range 0 to in_count_c-1;
  signal route_ready_s : std_ulogic;
  signal route_header_out_s : byte_string(0 to out_header_length_c-1);
  signal route_destination_s : natural range 0 to out_count_c-1;
  signal route_drop_s : std_ulogic;

  shared variable master_q0, master_q1, master_q2: frame_queue_root_t;
  shared variable slave_q0, slave_q1: frame_queue_root_t;
  shared variable check_q0, check_q1: frame_queue_root_t;

  constant cfg_c: config_t := config(1, last => true);

begin

  -- Test stimulus generator
  test: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
    variable frame_data : byte_string(0 to 63);
    variable header_v : byte_string(0 to in_header_length_c-1);
    variable out_header_v : byte_string(0 to out_header_length_c-1);
    variable dest_v : natural;
  begin
    done_s(0) <= '0';
    frame_queue_init(master_q0);
    frame_queue_init(master_q1);
    frame_queue_init(master_q2);
    frame_queue_init(slave_q0);
    frame_queue_init(slave_q1);
    frame_queue_init(check_q0);
    frame_queue_init(check_q1);

    wait for 40 ns;

    -- Generate test frames for each input port
    for frame_count in 0 to 11
    loop
      frame_byte_count := 4 + (frame_count mod 8);

      -- Generate frame data (header + payload)
      frame_data(0 to frame_byte_count-1) := prbs_byte_string(state_v, prbs31, frame_byte_count);
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);

      -- Extract header and determine destination
      header_v := frame_data(0 to in_header_length_c-1);
      dest_v := to_integer(unsigned(header_v(0))) mod out_count_c;

      -- Create output header (input header + source port)
      out_header_v(0 to in_header_length_c-1) := header_v;
      out_header_v(out_header_length_c-1) := to_byte(frame_count mod in_count_c);

      -- Send to appropriate input port and expect on corresponding output
      case frame_count mod in_count_c is
        when 0 =>
          frame_queue_put(master_q0, frame_data(0 to frame_byte_count-1));
          log_info("Input 0: Sending " & to_string(frame_byte_count) & " bytes to output " & to_string(dest_v));
        when 1 =>
          frame_queue_put(master_q1, frame_data(0 to frame_byte_count-1));
          log_info("Input 1: Sending " & to_string(frame_byte_count) & " bytes to output " & to_string(dest_v));
        when 2 =>
          frame_queue_put(master_q2, frame_data(0 to frame_byte_count-1));
          log_info("Input 2: Sending " & to_string(frame_byte_count) & " bytes to output " & to_string(dest_v));
        when others =>
          null;
      end case;

      -- Queue expected output (output header + payload without input header)
      if dest_v = 0 then
        frame_queue_put(check_q0, out_header_v & frame_data(in_header_length_c to frame_byte_count-1));
      else
        frame_queue_put(check_q1, out_header_v & frame_data(in_header_length_c to frame_byte_count-1));
      end if;
    end loop;

    frame_queue_drain(cfg_c, master_q0, timeout => 1 ms);
    frame_queue_drain(cfg_c, master_q1, timeout => 1 ms);
    frame_queue_drain(cfg_c, master_q2, timeout => 1 ms);
    wait for 10 us;

    frame_queue_assert_equal(cfg_c, slave_q0, check_q0);
    frame_queue_assert_equal(cfg_c, slave_q1, check_q1);

    log_info("Router test passed");
    done_s(0) <= '1';
    wait;
  end process;

  -- Routing decision logic
  router_logic: process(clock_s, reset_n_s)
    variable dest_v : natural;
  begin
    if reset_n_s = '0' then
      route_ready_s <= '0';
      route_destination_s <= 0;
      route_drop_s <= '0';
      route_header_out_s <= (others => x"00");
    elsif rising_edge(clock_s) then
      route_ready_s <= '0';

      if route_valid_s = '1' and route_ready_s = '0' then
        -- Decide destination based on first byte of header (LSB determines output port)
        dest_v := to_integer(unsigned(route_header_s(0))) mod out_count_c;

        -- Create output header: input header + source port number
        route_header_out_s(0 to in_header_length_c-1) <= route_header_s;
        route_header_out_s(out_header_length_c-1) <= to_byte(route_source_s);

        route_destination_s <= dest_v;
        route_drop_s <= '0';
        route_ready_s <= '1';

        log_info("Router: Source " & to_string(route_source_s) &
                 " header " & to_string(route_header_s) &
                 " -> Output " & to_string(dest_v));
      end if;
    end if;
  end process;

  -- Input port 0 master process
  master_proc0: process is
  begin
    in_s(0) <= transfer_defaults(cfg_c);
    wait for 40 ns;
    frame_queue_master(cfg_c, master_q0, clock_s, in_ack_s(0), in_s(0));
  end process;

  -- Input port 1 master process
  master_proc1: process is
  begin
    in_s(1) <= transfer_defaults(cfg_c);
    wait for 40 ns;
    frame_queue_master(cfg_c, master_q1, clock_s, in_ack_s(1), in_s(1));
  end process;

  -- Input port 2 master process
  master_proc2: process is
  begin
    in_s(2) <= transfer_defaults(cfg_c);
    wait for 40 ns;
    frame_queue_master(cfg_c, master_q2, clock_s, in_ack_s(2), in_s(2));
  end process;

  -- Output port 0 slave process
  slave_proc0: process is
  begin
    out_ack_s(0) <= accept(cfg_c, false);
    wait for 40 ns;
    frame_queue_slave(cfg_c, slave_q0, clock_s, out_s(0), out_ack_s(0));
  end process;

  -- Output port 1 slave process
  slave_proc1: process is
  begin
    out_ack_s(1) <= accept(cfg_c, false);
    wait for 40 ns;
    frame_queue_slave(cfg_c, slave_q1, clock_s, out_s(1), out_ack_s(1));
  end process;

  -- DUT instantiation
  dut: nsl_amba.stream_routing.axi4_stream_router
    generic map(
      config_c => cfg_c,
      in_count_c => in_count_c,
      out_count_c => out_count_c,
      in_header_length_c => in_header_length_c,
      out_header_length_c => out_header_length_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => in_s,
      in_o => in_ack_s,

      out_o => out_s,
      out_i => out_ack_s,

      route_valid_o => route_valid_s,
      route_header_o => route_header_s,
      route_source_o => route_source_s,

      route_ready_i => route_ready_s,
      route_header_i => route_header_out_s,
      route_destination_i => route_destination_s,
      route_drop_i => route_drop_s
      );

  -- Clock and reset driver
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

end architecture;
