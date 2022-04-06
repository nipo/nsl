library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc, nsl_inet;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_bnoc.testing.all;
use nsl_inet.ethernet.fcs_params_c;
use nsl_inet.ethernet.frame_pack;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

begin

  adder: block
    signal in_s, out_s : nsl_bnoc.committed.committed_bus;
    signal header_s : byte_string(0 to 3);
    signal header_valid_s : std_ulogic;
  begin
    gen: process
    begin
      in_s.req.valid <= '0';
      header_s <= (others => x"00");
      header_valid_s <= '0';

      wait for 100 ns;
      header_s <= from_hex("deadbeef");
      header_valid_s <= '1';
      wait for 20 ns;
      header_valid_s <= '0';
      wait for 10 ns;
      header_s <= from_hex("decafbad");

      committed_put(in_s.req, in_s.ack, clock_s,
                    from_hex("0123456789"), true,
                    1, 3);

      wait for 100 ns;
      header_s <= from_hex("12345678");
      header_valid_s <= '1';
      wait for 20 ns;
      header_valid_s <= '0';
      wait for 10 ns;
      header_s <= from_hex("00000000");

      committed_put(in_s.req, in_s.ack, clock_s,
                    from_hex(""), true,
                    1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(0) <= '0';

      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("adder check",
                      out_s.req, out_s.ack, clock_s,
                      from_hex("deadbeef0123456789"), true, LOG_LEVEL_FATAL,
                      1, 2);

      committed_check("adder check",
                      out_s.req, out_s.ack, clock_s,
                      from_hex("12345678"), true, LOG_LEVEL_FATAL,
                      1, 2);
      
      done_s(0) <= '1';
      wait;
    end process;
    
    dut: nsl_bnoc.committed.committed_header_inserter
      generic map(
        header_length_c => header_s'length
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        capture_i => header_valid_s,
        header_i => header_s,
        in_i => in_s.req,
        in_o => in_s.ack,
        out_o => out_s.req,
        out_i => out_s.ack
        );
  end block;

  extractor: block
    signal in_s, out_s : nsl_bnoc.committed.committed_bus;
    signal header_s : byte_string(0 to 3);
    signal header_valid_s : std_ulogic;
  begin
    gen: process
    begin
      in_s.req.valid <= '0';

      committed_put(in_s.req, in_s.ack, clock_s,
                    from_hex("deadbeef0123456789"), true,
                    1, 3);

      committed_put(in_s.req, in_s.ack, clock_s,
                    from_hex("feedfeed9876543210"), true,
                    1, 3);
      wait;
    end process;

    data_chk: process
    begin
      done_s(1) <= '0';

      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("extractor check",
                      out_s.req, out_s.ack, clock_s,
                      from_hex("0123456789"), true, LOG_LEVEL_FATAL,
                      1, 2);

      committed_check("extractor check",
                      out_s.req, out_s.ack, clock_s,
                      from_hex("9876543210"), true, LOG_LEVEL_FATAL,
                      1, 3);
      
      done_s(1) <= '1';
      wait;
    end process;

    header_chk: process
    begin
      done_s(2) <= '0';

      while true
      loop
        wait until rising_edge(clock_s);
        if header_valid_s = '1' then
          exit;
        end if;
      end loop;
      assert_equal("header check", header_s, from_hex("deadbeef"), FAILURE);

      while true
      loop
        wait until rising_edge(clock_s);
        if header_valid_s = '1' then
          exit;
        end if;
      end loop;
      assert_equal("header check", header_s, from_hex("feedfeed"), FAILURE);
      
      done_s(2) <= '1';
      wait;
    end process;
    
    dut: nsl_bnoc.committed.committed_header_extractor
      generic map(
        header_length_c => header_s'length
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        valid_o => header_valid_s,
        header_o => header_s,
        in_i => in_s.req,
        in_o => in_s.ack,
        out_o => out_s.req,
        out_i => out_s.ack
        );
  end block;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

  
end;
