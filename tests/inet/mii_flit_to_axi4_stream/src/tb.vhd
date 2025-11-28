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
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.text.all;

architecture arch of tb is

    signal clock_s, reset_n_s, valid_s : std_ulogic;
    signal done_s : std_ulogic_vector(0 to 0);
    signal out_s, out_flit_to_axi_s, out_paced_s : bus_t;
    signal flit_s : mii_flit_t;
    signal flit_axi_s : bus_t;
    signal error_s : std_ulogic;

    signal user_flip_s : boolean := false;
    signal user_flip_beat_s : integer := 0;

    shared variable in_flit_q, out_axi_q : frame_queue_root_t;

begin

    gen_scenario_proc : process
        constant preamble_offset : integer := 7;
        constant MPS_real : real := real(1500);
        variable rx_frm : frame_t;
        variable pkt_played_v, size_v : integer := 0;
        variable seed1_v : positive := 42;
        variable seed2_v : positive := 123;
        variable rand_v : real;
        variable state_v1_v : prbs_state(30 downto 0) := x"deadbee" & "111";
    begin
        done_s <= (others => '0');
        frame_queue_init(in_flit_q);
        frame_queue_init(out_axi_q);

        wait until reset_n_s = '1';
        log_info("===== Test 1: Normal packet (should pass through) =====");
        send_and_check_packet(
          clock_s,
          in_flit_q,
          out_axi_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => eth_packet_overhead_adder(from_hex("01234567")),
          data2 => from_hex("01234567"));

        wait for 100 ns;
        log_info("===== Test 2: Error Preamble (should pass through) =====");
        send_packet_with_error(
          clock_s,
          in_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data => eth_packet_overhead_adder(from_hex("a0a0a0a0a0a0")),
          error_beat => 0);
          -- If an error orccurs in the preamble, the packet is forwarded.
          -- This frame queue get is just used to pop the prev frame.
          frame_queue_get(out_axi_q, rx_frm);

        wait for 100 ns;
        log_info("===== Test 3: Error SFD (should be dropped) =====");
        send_packet_with_error(
          clock_s,
          in_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data => eth_packet_overhead_adder(from_hex("ffffffffff")),
          error_beat => preamble_offset + 1);

        wait for 100 ns;
        log_info("===== Test 4: Error DATA (should be dropped) =====");
          send_packet_with_error(
          clock_s,
          in_flit_q,
          user_flip_s,
          user_flip_beat_s,
          data => eth_packet_overhead_adder(byte_range(x"00", x"ff")),
          error_beat => preamble_offset + 3);

        wait for 100 ns;
        log_info("===== Test 5: Normal packet (should pass through) =====");
        send_and_check_packet(
          clock_s,
          in_flit_q,
          out_axi_q,
          user_flip_s,
          user_flip_beat_s,
          data1 => eth_packet_overhead_adder(from_hex("01234567")),
          data2 => from_hex("01234567"));

        log_info("===== Some random packets =====");
        while pkt_played_v /= 200
            loop
                uniform(seed1_v, seed2_v, rand_v);
                size_v := integer(rand_v * MPS_real);
                send_and_check_packet(
                clock_s,
                in_flit_q,
                out_axi_q,
                user_flip_s,
                user_flip_beat_s,
                data1 => eth_packet_overhead_adder(prbs_byte_string(state_v1_v, prbs31, size_v)),
                data2 => prbs_byte_string(state_v1_v, prbs31, size_v));
                state_v1_v := prbs_forward(state_v1_v, prbs31, size_v);
                pkt_played_v := pkt_played_v + 1;
                if pkt_played_v mod 10 = 0 then
                    log_info("INFO: packets played " & to_string(pkt_played_v));
                end if;
            end loop;

            wait for 100 ns;
            done_s <= (others => '1');
            wait;
        end process;

        dut : nsl_mii.flit.mii_flit_to_axi4_stream
        port map(
            reset_n_i => reset_n_s,
            clock_i   => clock_s,

            flit_i  => flit_s,
            valid_i => valid_s,

            out_o => out_flit_to_axi_s.m,
            out_i => out_flit_to_axi_s.s
        );

        flit_s.data <= bytes(axi4_flit_cfg, flit_axi_s.m)(0);
        flit_s.valid <= to_logic(is_valid(axi4_flit_cfg, flit_axi_s.m));
        flit_s.error <= and_reduce(user(axi4_flit_cfg, flit_axi_s.m));

        flit_axi_s.s <= accept(axi4_flit_cfg, true);

        valid_s <= '1';

        error_s <= user(axi4_flit_cfg, out_flit_to_axi_s.m)(0);

        pkt_cleaner : nsl_amba.stream_fifo.axi4_stream_fifo_clean
        generic map (
            config_c => axi4_flit_cfg
        )
        port map(
            reset_n_i => reset_n_s,
            clock_i   => clock_s,
    
            in_error_i => error_s,
            in_i => out_flit_to_axi_s.m,
            in_o => out_flit_to_axi_s.s,
    
            out_o => out_s.m,
            out_i => out_s.s
        );

        pkt_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
        generic map(
            config_c               => config(1, user => 1, last => true),
            probability_denom_l2_c => 30,
            probability_c          => 0.30
        )
        port map(
            reset_n_i => reset_n_s,
            clock_i   => clock_s,

            in_i => out_s.m,
            in_o => out_s.s,

            out_o => out_paced_s.m,
            out_i => out_paced_s.s
        );

        flit_master : process is
        begin
            flit_axi_s.m <= transfer_defaults(axi4_flit_cfg);
            wait for 40 ns;
            if in_flit_q.head /= null then
                frame_queue_master(axi4_flit_cfg, user_flip_s, user_flip_beat_s, in_flit_q, clock_s, flit_axi_s.s, flit_axi_s.m, timeout => 10000 us);
            end if;
        end process;

        axi_slave : process is
        begin
            out_paced_s.s <= accept(axi4_flit_cfg, false);
            wait for 40 ns;
            frame_queue_slave(cfg => axi4_flit_cfg,
            root => out_axi_q,
            clock => clock_s,
            stream_i => out_paced_s.m,
            stream_o => out_paced_s.s);
        end process;

        -- axi_stream_in_dumper : nsl_amba.axi4_stream.axi4_stream_dumper
        -- generic map(
        --     config_c => axi4_flit_cfg,
        --     prefix_c => "AXI-STREAM-IN"
        -- )
        -- port map(
        --     clock_i   => clock_s,
        --     reset_n_i => reset_n_s,

        --     bus_i.m => flit_axi_s.m,
        --     bus_i.s => flit_axi_s.s
        -- );

        -- axi_stream_out_dumper : nsl_amba.axi4_stream.axi4_stream_dumper
        -- generic map(
        --     config_c => axi4_flit_cfg,
        --     prefix_c => "AXI-STREAM-OUT"
        -- )
        -- port map(
        --     clock_i   => clock_s,
        --     reset_n_i => reset_n_s,

        --     bus_i.m => out_paced_s.m,
        --     bus_i.s => out_paced_s.s
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
