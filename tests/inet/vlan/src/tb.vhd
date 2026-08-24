library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_bnoc, nsl_inet;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_bnoc.testing.all;
use nsl_inet.vlan.all;

entity tb is
end tb;

architecture arch of tb is

  constant vlan_id_list_c : vlan_id_vector(0 to 1) := (100, 200);

  constant da_c : byte_string := from_hex("020000000001");
  constant sa_c : byte_string := from_hex("020000000002");

  constant untagged_frame_c : byte_string
    := da_c & sa_c & from_hex("1234") & from_hex("deadbeef");
  -- VID 100, PCP/DEI zero
  constant v100_tagged_c : byte_string
    := da_c & sa_c & from_hex("81000064") & from_hex("0800") & from_hex("cafe0001");
  constant v100_untagged_c : byte_string
    := da_c & sa_c & from_hex("0800") & from_hex("cafe0001");
  -- VID 200, PCP 7 on input, priority is discarded
  constant v200_tagged_pcp_c : byte_string
    := da_c & sa_c & from_hex("8100e0c8") & from_hex("0806") & from_hex("0102");
  constant v200_tagged_c : byte_string
    := da_c & sa_c & from_hex("810000c8") & from_hex("0806") & from_hex("0102");
  constant v200_untagged_c : byte_string
    := da_c & sa_c & from_hex("0806") & from_hex("0102");
  -- VID 300, not in the configured list
  constant v300_tagged_c : byte_string
    := da_c & sa_c & from_hex("8100012c") & from_hex("0800") & from_hex("aa");

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 4);

begin

  demux: block
    signal in_s, untagged_s : nsl_bnoc.committed.committed_bus;
    signal tagged_req_s : nsl_bnoc.committed.committed_req_array(0 to 1);
    signal tagged_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 1);
  begin
    gen: process
    begin
      in_s.req.valid <= '0';
      wait for 100 ns;

      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    v100_tagged_c, true, 1, 3);
      -- Unknown VID, must be dropped
      committed_put(in_s.req, in_s.ack, clock_s,
                    v300_tagged_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    v200_tagged_pcp_c, true, 1, 3);
      -- Cancelled frame, forwarded cancelled
      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, false, 1, 3);
      wait;
    end process;

    untagged_chk: process
    begin
      done_s(0) <= '0';
      untagged_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("demux untagged",
                      untagged_s.req, untagged_s.ack, clock_s,
                      untagged_frame_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("demux untagged cancelled",
                      untagged_s.req, untagged_s.ack, clock_s,
                      untagged_frame_c, false, LOG_LEVEL_FATAL, 1, 2);

      done_s(0) <= '1';
      wait;
    end process;

    v100_chk: process
    begin
      done_s(1) <= '0';
      tagged_ack_s(0).ready <= '0';
      wait for 100 ns;

      committed_check("demux vid 100",
                      tagged_req_s(0), tagged_ack_s(0), clock_s,
                      v100_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(1) <= '1';
      wait;
    end process;

    v200_chk: process
    begin
      done_s(2) <= '0';
      tagged_ack_s(1).ready <= '0';
      wait for 100 ns;

      committed_check("demux vid 200",
                      tagged_req_s(1), tagged_ack_s(1), clock_s,
                      v200_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(2) <= '1';
      wait;
    end process;

    dut: nsl_inet.vlan.vlan_demux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => in_s.req,
        in_o => in_s.ack,

        untagged_o => untagged_s.req,
        untagged_i => untagged_s.ack,

        tagged_o => tagged_req_s,
        tagged_i => tagged_ack_s
        );
  end block;

  mux: block
    signal untagged_s, out_s : nsl_bnoc.committed.committed_bus;
    signal tagged_req_s : nsl_bnoc.committed.committed_req_array(0 to 1);
    signal tagged_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 1);
  begin
    gen: process
    begin
      untagged_s.req.valid <= '0';
      tagged_req_s(0).valid <= '0';
      tagged_req_s(1).valid <= '0';
      wait for 100 ns;

      committed_put(untagged_s.req, untagged_s.ack, clock_s,
                    untagged_frame_c, true, 1, 3);
      committed_put(tagged_req_s(0), tagged_ack_s(0), clock_s,
                    v100_untagged_c, true, 1, 3);
      committed_put(tagged_req_s(1), tagged_ack_s(1), clock_s,
                    v200_untagged_c, true, 1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(3) <= '0';
      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("mux untagged",
                      out_s.req, out_s.ack, clock_s,
                      untagged_frame_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("mux vid 100",
                      out_s.req, out_s.ack, clock_s,
                      v100_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("mux vid 200",
                      out_s.req, out_s.ack, clock_s,
                      v200_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(3) <= '1';
      wait;
    end process;

    dut: nsl_inet.vlan.vlan_mux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        untagged_i => untagged_s.req,
        untagged_o => untagged_s.ack,

        tagged_i => tagged_req_s,
        tagged_o => tagged_ack_s,

        out_o => out_s.req,
        out_i => out_s.ack
        );
  end block;

  loopback: block
    signal in_s, mid_s, untagged_mid_s, out_s : nsl_bnoc.committed.committed_bus;
    signal demux_tagged_req_s, mux_tagged_req_s : nsl_bnoc.committed.committed_req_array(0 to 1);
    signal demux_tagged_ack_s, mux_tagged_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 1);
  begin
    gen: process
    begin
      in_s.req.valid <= '0';
      wait for 100 ns;

      committed_put(in_s.req, in_s.ack, clock_s,
                    v100_tagged_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    v200_tagged_pcp_c, true, 1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(4) <= '0';
      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("loopback vid 100",
                      out_s.req, out_s.ack, clock_s,
                      v100_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("loopback untagged",
                      out_s.req, out_s.ack, clock_s,
                      untagged_frame_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("loopback vid 200",
                      out_s.req, out_s.ack, clock_s,
                      v200_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(4) <= '1';
      wait;
    end process;

    demux: nsl_inet.vlan.vlan_demux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => in_s.req,
        in_o => in_s.ack,

        untagged_o => untagged_mid_s.req,
        untagged_i => untagged_mid_s.ack,

        tagged_o => demux_tagged_req_s,
        tagged_i => demux_tagged_ack_s
        );

    mux_tagged_req_s <= demux_tagged_req_s;
    demux_tagged_ack_s <= mux_tagged_ack_s;

    mux: nsl_inet.vlan.vlan_mux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        untagged_i => untagged_mid_s.req,
        untagged_o => untagged_mid_s.ack,

        tagged_i => mux_tagged_req_s,
        tagged_o => mux_tagged_ack_s,

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
