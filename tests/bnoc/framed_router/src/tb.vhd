library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_bnoc;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

  signal in0_s, in1_s, out0_s, out1_s, out2_s : nsl_bnoc.framed.framed_bus;
  signal route_valid_s, route_ready_s, route_drop_s: std_ulogic;
  signal route_in_header_s : byte_string(0 to 0);
  signal route_out_header_s : byte_string(0 to 3);
  signal route_destination_s : integer range 0 to 2;

begin

  in0_gen: process
  begin
    in0_s.req.valid <= '0';

    wait for 34 ns;
    framed_put(in0_s.req, in0_s.ack, clock_s,
               from_hex("01") & to_byte_string("Message from 0 to 1"),
               1, 4);
    wait for 67 ns;
    framed_put(in0_s.req, in0_s.ack, clock_s,
               from_hex("02") & to_byte_string("Message from 0 to 2"),
               1, 4);
    framed_put(in0_s.req, in0_s.ack, clock_s,
               from_hex("00") & to_byte_string("Message from 0 to 0"),
               1, 4);
    wait;
  end process;

  in1_gen: process
  begin
    in1_s.req.valid <= '0';

    wait for 37 ns;
    framed_put(in1_s.req, in1_s.ack, clock_s,
               from_hex("12") & to_byte_string("Message from 1 to 2"),
               1, 4);
    wait for 34 ns;
    framed_put(in1_s.req, in1_s.ack, clock_s,
               from_hex("11") & to_byte_string("Message from 1 to 1"),
               1, 4);
    framed_put(in1_s.req, in1_s.ack, clock_s,
               from_hex("10") & to_byte_string("Message from 1 to 0"),
               1, 4);
    wait;
  end process;
  
  router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => 2,
      out_count_c => 3,
      in_header_count_c => 1,
      out_header_count_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i(0) => in0_s.req,
      in_i(1) => in1_s.req,
      in_o(0) => in0_s.ack,
      in_o(1) => in1_s.ack,
      
      out_o(0) => out0_s.req,
      out_o(1) => out1_s.req,
      out_o(2) => out2_s.req,
      out_i(0) => out0_s.ack,
      out_i(1) => out1_s.ack,
      out_i(2) => out2_s.ack,

      route_valid_o => route_valid_s,
      route_ready_i => route_ready_s,
      route_header_o => route_in_header_s,
      route_header_i => route_out_header_s,
      route_destination_i => route_destination_s,
      route_drop_i => route_drop_s
      );

  out0_chk: process
  begin
    done_s(0) <= '0';
    out0_s.ack.ready <= '0';

    wait for 10 ns;

    framed_check("chk0 10",
                 out0_s.req, out0_s.ack, clock_s,
                 from_hex("ffdead10") & to_byte_string("Message from 1 to 0"), LOG_LEVEL_WARNING,
                 1, 3);

    framed_check("chk0 00",
                 out0_s.req, out0_s.ack, clock_s,
                 from_hex("ffdead00") & to_byte_string("Message from 0 to 0"), LOG_LEVEL_WARNING,
                 1, 3);


    done_s(0) <= '1';
    wait;
  end process;

  out1_chk: process
  begin
    done_s(1) <= '0';
    out1_s.ack.ready <= '0';

    wait for 10 ns;

    framed_check("chk1 01",
                 out1_s.req, out1_s.ack, clock_s,
                 from_hex("ffdead01") & to_byte_string("Message from 0 to 1"), LOG_LEVEL_WARNING,
                 1, 3);

    framed_check("chk1 11",
                 out1_s.req, out1_s.ack, clock_s,
                 from_hex("ffdead11") & to_byte_string("Message from 1 to 1"), LOG_LEVEL_WARNING,
                 1, 3);


    done_s(1) <= '1';
    wait;
  end process;

  out2_chk: process
  begin
    done_s(2) <= '0';
    out2_s.ack.ready <= '0';

    wait for 10 ns;

    framed_check("chk2 12",
                 out2_s.req, out2_s.ack, clock_s,
                 from_hex("ffdead12") & to_byte_string("Message from 1 to 2"), LOG_LEVEL_WARNING,
                 1, 4);

    framed_check("chk2 02",
                 out2_s.req, out2_s.ack, clock_s,
                 from_hex("ffdead02") & to_byte_string("Message from 0 to 2"), LOG_LEVEL_WARNING,
                 1, 4);


    done_s(2) <= '1';
    wait;
  end process;

  route: process(route_valid_s, route_in_header_s) is
  begin
    route_ready_s <= '1';
    route_drop_s <= '0';
    route_out_header_s(0 to 2) <= from_hex("ffdead");
    route_out_header_s(3) <= route_in_header_s(0);
    route_destination_s <= to_integer(unsigned(route_in_header_s(0)(3 downto 0)));
  end process;
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 1 ns,
      reset_duration => (others => 7 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

  
end;
