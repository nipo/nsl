library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;

-- Router line-rate covenant test.
--
-- One input, two outputs, 16-byte input header, 8-byte output
-- header, at 1, 2 and 4 byte stream widths.
--
-- Phase one sends back-to-back packets separated by an
-- ethernet-scaled interpacket gap (20 byte times), with always-ready
-- consumers, and a backpressure monitor proves the router input
-- never stalls.  The mix includes minimum-size packets, packets with
-- a partial last beat, header-only packets, dropped packets and
-- runts.
--
-- Phase two sends the same kind of traffic against consumers that
-- stall randomly, exercising packet capture and routing while
-- previous packets are still being delivered to distinct
-- backpressured outputs.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

  constant in_header_length_c : natural := 16;
  constant out_header_length_c : natural := 8;
  constant phase1_count_c : natural := 60;
  constant total_count_c : natural := 100;

  function gen_len(idx: integer) return integer
  is
  begin
    if idx mod 10 = 7 then
      -- Runt, shorter than the header
      return 8;
    elsif idx mod 10 = 3 then
      -- Header-only packet
      return in_header_length_c;
    elsif idx mod 4 = 1 then
      -- Partial last beat at wide configs
      return 61 + (idx mod 3);
    else
      -- Minimum ethernet frame
      return 64;
    end if;
  end function;

  function gen_dest(idx: integer) return integer
  is
  begin
    -- Pairs of consecutive packets to the same output, then switch
    return (idx / 2) mod 2;
  end function;

  function gen_drop(idx: integer) return boolean
  is
  begin
    return idx mod 10 = 5;
  end function;

  function gen_data(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to gen_len(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 7 + k * 13) mod 256);
    end loop;
    ret(0) := to_byte(idx mod 256);
    ret(2) := to_byte(gen_dest(idx));
    ret(3) := to_byte(if_else(gen_drop(idx), 255, 0));
    return ret;
  end function;

begin

  w_gen: for wl2 in 0 to 2 generate
    constant width_c : natural := 2 ** wl2;
    constant cfg_c: config_t := config(bytes => width_c, user => 1,
                                       keep => true, last => true);
    constant ipg_beats_c : natural := 20 / width_c;

    signal input_s : bus_t;
    signal output_s : bus_vector(0 to 1);
    signal monitor_en_s : std_ulogic;

    signal route_valid_s : std_ulogic;
    signal route_header_s : byte_string(0 to in_header_length_c-1);
    signal route_source_s : natural range 0 to 0;
    signal route_ready_s : std_ulogic;
    signal route_out_header_s : byte_string(0 to out_header_length_c-1);
    signal route_destination_s : natural range 0 to 1;
    signal route_drop_s : std_ulogic;
  begin

    stim: process is
      variable pkt_v: byte_string(0 to 63);
      variable len_v, beats_v, first_v, nbytes_v: integer;
      variable chunk_v: byte_string(0 to cfg_c.data_width-1);
      variable keep_v: std_ulogic_vector(0 to cfg_c.data_width-1);
    begin
      input_s.m <= transfer_defaults(cfg_c);
      monitor_en_s <= '1';
      wait for 100 ns;
      wait until falling_edge(clock_s);

      for idx in 0 to total_count_c-1
      loop
        if idx = phase1_count_c then
          -- Let phase one drain, then run without the line-rate
          -- covenant against stalling consumers
          monitor_en_s <= '0';
          for i in 0 to 63
          loop
            wait until falling_edge(clock_s);
          end loop;
        end if;

        len_v := gen_len(idx);
        pkt_v(0 to len_v-1) := gen_data(idx);
        beats_v := (len_v + width_c - 1) / width_c;

        for b in 0 to beats_v-1
        loop
          first_v := b * width_c;
          nbytes_v := width_c;
          if first_v + nbytes_v > len_v then
            nbytes_v := len_v - first_v;
          end if;

          chunk_v := (others => x"00");
          keep_v := (others => '0');
          for k in 0 to nbytes_v-1
          loop
            chunk_v(k) := pkt_v(first_v + k);
            keep_v(k) := '1';
          end loop;

          -- Header-only packets carry a set user bit, checked on the
          -- output side: with no payload beat, the flag must ride the
          -- generated response header.
          if len_v = in_header_length_c then
            input_s.m <= transfer(cfg_c,
                                  bytes => chunk_v,
                                  keep => keep_v,
                                  user => "1",
                                  valid => true,
                                  last => b = beats_v-1);
          else
            input_s.m <= transfer(cfg_c,
                                  bytes => chunk_v,
                                  keep => keep_v,
                                  user => "0",
                                  valid => true,
                                  last => b = beats_v-1);
          end if;
          loop
            wait until rising_edge(clock_s);
            exit when is_ready(cfg_c, input_s.s);
          end loop;
          wait until falling_edge(clock_s);
        end loop;

        input_s.m <= transfer_defaults(cfg_c);
        for i in 1 to ipg_beats_c
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;
      wait;
    end process;

    route: process(clock_s, reset_n_s) is
    begin
      if reset_n_s = '0' then
        route_ready_s <= '0';
        route_drop_s <= '0';
        route_destination_s <= 0;
        route_out_header_s <= (others => x"00");
      elsif rising_edge(clock_s) then
        route_ready_s <= '0';

        if route_valid_s = '1' and route_ready_s = '0' then
          route_destination_s <= to_integer(unsigned(route_header_s(2))) mod 2;
          route_drop_s <= to_logic(route_header_s(3) = x"ff");
          route_out_header_s <= route_header_s(0 to out_header_length_c-1);
          route_ready_s <= '1';
        end if;
      end if;
    end process;

    out_gen: for o in 0 to 1 generate
    begin
      check: process is
        variable pkt_v, exp_v: byte_string(0 to 63);
        variable len_v, exp_len_v, stall_v: integer;
        variable beat_v: master_t;
        variable rx_v: byte_stream;
      begin
        output_s(o).s <= accept(cfg_c, false);
        wait for 40 ns;

        for idx in 0 to total_count_c-1
        loop
          len_v := gen_len(idx);
          next when len_v < in_header_length_c;
          next when gen_drop(idx);
          next when gen_dest(idx) /= o;

          pkt_v(0 to len_v-1) := gen_data(idx);
          exp_len_v := len_v - in_header_length_c + out_header_length_c;
          exp_v(0 to out_header_length_c-1) := pkt_v(0 to out_header_length_c-1);
          exp_v(out_header_length_c to exp_len_v-1)
            := pkt_v(in_header_length_c to len_v-1);

          clear(rx_v);
          loop
            if idx >= phase1_count_c then
              stall_v := (idx + rx_v.all'length) * 7 mod 4;
              output_s(o).s <= accept(cfg_c, false);
              for i in 1 to stall_v
              loop
                wait until falling_edge(clock_s);
              end loop;
            end if;

            receive(cfg_c, clock_s, output_s(o).m, output_s(o).s, beat_v);

            for k in 0 to byte_count(cfg_c, beat_v)-1
            loop
              write(rx_v, beat_v.data(k));
            end loop;

            if is_last(cfg_c, beat_v) then
              assert (beat_v.user(0) = '1')
                = (gen_len(idx) = in_header_length_c)
                report "W" & to_string(width_c)
                & " out " & to_string(o)
                & " packet " & to_string(idx)
                & ": unexpected last beat user bit"
                severity failure;
              exit;
            end if;
          end loop;

          assert_equal("W" & to_string(width_c)
                       & " out " & to_string(o)
                       & " packet " & to_string(idx),
                       rx_v.all, exp_v(0 to exp_len_v-1), failure);
          deallocate(rx_v);
        end loop;

        log_info("W" & to_string(width_c)
                 & " output " & to_string(o) & " OK");
        done_s(wl2 * 2 + o) <= '1';
        wait;
      end process;
    end generate;

    monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "ROUTER_IN_W" & to_string(width_c),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        enable_i => monitor_en_s,
        bus_i => input_s
        );

    dut: nsl_amba.stream_routing.axi4_stream_router
      generic map(
        config_c => cfg_c,
        in_count_c => 1,
        out_count_c => 2,
        in_header_length_c => in_header_length_c,
        out_header_length_c => out_header_length_c,
        fifo_depth_c => 16
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        in_i(0) => input_s.m,
        in_o(0) => input_s.s,

        out_o(0) => output_s(0).m,
        out_o(1) => output_s(1).m,
        out_i(0) => output_s(0).s,
        out_i(1) => output_s(1).s,

        route_valid_o => route_valid_s,
        route_header_o => route_header_s,
        route_source_o => route_source_s,

        route_ready_i => route_ready_s,
        route_header_i => route_out_header_s,
        route_destination_i => route_destination_s,
        route_drop_i => route_drop_s
        );
  end generate;

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
