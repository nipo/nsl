library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_data, nsl_amba, nsl_logic;
use nsl_simulation.logging.all;
use nsl_mii.rgmii.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.flit.all;
use nsl_mii.testing.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.prbs.all;

architecture arch of tb is

    signal clock_s, reset_n_s : std_ulogic;
    signal done_s : std_ulogic_vector(0 to 0);
    signal in_s, out_s : bus_t;
    signal flit_s : mii_flit_t;
    signal underrun_s, packet_s, ready_s, error_s : std_ulogic;
    signal axi_flit_master_s : bus_t;

    signal user_flip_s : boolean := false;
    signal user_flip_beat_s : integer := 0;

    shared variable in_axi_q, out_flit_q : frame_queue_root_t;

begin

    gen_scenario_proc : process
        constant MPS_real : real := real(1500);
        variable pkt_played_v, size_v, error_beat_v : integer := 0;
        variable seed1_v : positive := 42;
        variable seed2_v : positive := 123;
        variable rand_v : real;
        variable state_v1_v : prbs_state(30 downto 0) := x"deadbee" & "111";
    begin
        done_s <= (others => '0');
        frame_queue_init(in_axi_q);
        frame_queue_init(out_flit_q);

        wait until reset_n_s = '1';
        log_info("===== Test 1: Normal packet (should pass through) =====");
        send_and_check_packet(
          clock_s,
          in_axi_q,
          out_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => from_hex("01234567"),
          data2 => eth_packet_overhead_adder(from_hex("01234567")));
        wait for 100 ns;
        log_info("===== Test 2: Normal packet (should pass through) =====");
        send_and_check_packet(
          clock_s,
          in_axi_q,
          out_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => from_hex("aaaaaaaaaaaaaaaaaaaaaaaa"),
          data2 => eth_packet_overhead_adder(from_hex("aaaaaaaaaaaaaaaaaaaaaaaa")));
        wait for 100 ns;
        log_info("===== Test 3:  Error in first byte (should be dropped) =====");
        send_packet_with_error(
          clock_s,
          in_axi_q,
          user_flip_s,
          user_flip_beat_s,
          data => from_hex("a0a0a0a0a0a0"),
          error_beat => 0);
        wait for 100 ns;
        log_info("===== Test 4: Normal packet (should pass through) =====");
        send_and_check_packet(
          clock_s,
          in_axi_q,
          out_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => from_hex("ffffffffff"),
          data2 => eth_packet_overhead_adder(from_hex("ffffffffff")));
        log_info("===== Test 5:  Error in last byte (should be dropped) =====");
        send_packet_with_error(
          clock_s,
          in_axi_q,
          user_flip_s,
          user_flip_beat_s,
          data => from_hex("121212121212"),
          error_beat => from_hex("121212121212")'right);
          log_info("===== Test 6: Long packet (should pass through) =====");
          send_and_check_packet(
          clock_s,
          in_axi_q,
          out_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => byte_range(x"00", x"ff") & byte_range(x"00", x"ff"),
          data2 => eth_packet_overhead_adder(byte_range(x"00", x"ff") & byte_range(x"00", x"ff")));
        log_info("===== Some random packets =====");
        while pkt_played_v /= 200 loop
            uniform(seed1_v, seed2_v, rand_v);
            size_v := integer(rand_v * MPS_real) + 1;
            if real(size_v) > MPS_real/2.0 then
                error_beat_v := integer(rand_v * real(size_v)) - 1;
                send_packet_with_error(
                clock_s,
                in_axi_q,
                user_flip_s,
                user_flip_beat_s,
                data => prbs_byte_string(state_v1_v, prbs31, size_v),
                error_beat => error_beat_v);
            else
                send_and_check_packet(
                clock_s,
                in_axi_q,
                out_flit_q,
                user_flip_s,
                user_flip_beat_s,
                data1 => prbs_byte_string(state_v1_v, prbs31, size_v),
                data2 => eth_packet_overhead_adder(prbs_byte_string(state_v1_v, prbs31, size_v)));
            end if;
            state_v1_v := prbs_forward(state_v1_v, prbs31, size_v);
            pkt_played_v := pkt_played_v + 1;
            if pkt_played_v mod 10 = 0 then
                log_info("INFO: packets played " & to_string(pkt_played_v));
            end if;
            wait for 1000 ns;
        end loop;

        wait for 100 ns;
        done_s <= (others => '1');
        wait;
    end process;

    dut : nsl_mii.flit.mii_flit_from_axi4_stream
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_i => in_s.m,
        in_o => in_s.s,

        underrun_o => underrun_s,
        packet_o   => packet_s,
        flit_o     => flit_s,
        ready_i    => ready_s
    );

    axi_flit_master_s.m <= transfer(cfg => axi4_flit_cfg,
                           bytes => from_suv(flit_s.data),
                           user => (0 => flit_s.error),
                           valid => to_boolean(flit_s.valid),
                           last => (packet_s = '0'));

    error_s <= (flit_s.error);
    ready_s <= to_logic(is_ready(axi4_flit_cfg, axi_flit_master_s.s));

    pkt_cleaner : nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map (
        config_c => axi4_flit_cfg
    )
    port map(
        reset_n_i => reset_n_s,
        clock_i   => clock_s,

        in_error_i => error_s,
        in_i => axi_flit_master_s.m,
        in_o => axi_flit_master_s.s,

        out_o => out_s.m,
        out_i => out_s.s
    );

    axi_master : process is
    begin
        in_s.m <= transfer_defaults(axi4_flit_cfg);
        wait for 40 ns;
        if in_axi_q.head /= null then
            frame_queue_master(axi4_flit_cfg, user_flip_s, user_flip_beat_s, in_axi_q, clock_s, in_s.s, in_s.m, timeout => 1000000 us);
        end if;
    end process;

    flit_slave : process is
    begin
        wait for 40 ns;
        frame_queue_slave(cfg => axi4_flit_cfg,
            root => out_flit_q,
            clock => clock_s,
            stream_i => out_s.m,
            stream_o => out_s.s);
    end process;

    -- axi_stream_in_dumper : nsl_amba.axi4_stream.axi4_stream_dumper
    -- generic map(
    --     config_c => axi4_flit_cfg,
    --     prefix_c => "AXI-STREAM-IN"
    -- )
    -- port map(
    --     clock_i   => clock_s,
    --     reset_n_i => reset_n_s,

    --     bus_i.m => in_s.m,
    --     bus_i.s => in_s.s
    -- );

    -- axi_stream_out_dumper : nsl_amba.axi4_stream.axi4_stream_dumper
    -- generic map(
    --     config_c => axi4_flit_cfg,
    --     prefix_c => "AXI-STREAM-OUT"
    -- )
    -- port map(
    --     clock_i   => clock_s,
    --     reset_n_i => reset_n_s,

    --     bus_i => out_s
    -- );

    driver : nsl_simulation.driver.simulation_driver
    generic map(
        clock_count => 1,
        reset_count => 1,
        done_count  => done_s'length
    )
    port map(
        clock_period(0)   => 8 ns,
        reset_duration(0) => 14 ns,
        reset_n_o(0)      => reset_n_s,
        clock_o(0)        => clock_s,
        done_i            => done_s
    );

end;
