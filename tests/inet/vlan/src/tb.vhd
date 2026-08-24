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

  -- VID 1 is the native VLAN
  constant vlan_id_list_c : vlan_id_vector(0 to 2) := (1, 100, 200);
  constant native_vlan_id_c : vlan_id_t := 1;

  constant da_c : byte_string := from_hex("020000000001");
  constant sa_c : byte_string := from_hex("020000000002");

  constant untagged_frame_c : byte_string
    := da_c & sa_c & from_hex("1234") & from_hex("deadbeef");
  -- Tagged with the native VID
  constant v1_tagged_c : byte_string
    := da_c & sa_c & from_hex("81000001") & from_hex("88b5") & from_hex("0304");
  constant v1_untagged_c : byte_string
    := da_c & sa_c & from_hex("88b5") & from_hex("0304");
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
  signal done_s: std_ulogic_vector(0 to 5);

begin

  demux: block
    signal in_s : nsl_bnoc.committed.committed_bus;
    signal vlan_req_s : nsl_bnoc.committed.committed_req_array(0 to 2);
    signal vlan_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 2);
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
      -- Tagged with the native VID, merged with untagged frames
      committed_put(in_s.req, in_s.ack, clock_s,
                    v1_tagged_c, true, 1, 3);
      -- Cancelled frame, forwarded cancelled
      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, false, 1, 3);
      wait;
    end process;

    native_chk: process
    begin
      done_s(0) <= '0';
      vlan_ack_s(0).ready <= '0';
      wait for 100 ns;

      committed_check("demux native untagged",
                      vlan_req_s(0), vlan_ack_s(0), clock_s,
                      untagged_frame_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("demux native tagged",
                      vlan_req_s(0), vlan_ack_s(0), clock_s,
                      v1_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("demux native cancelled",
                      vlan_req_s(0), vlan_ack_s(0), clock_s,
                      untagged_frame_c, false, LOG_LEVEL_FATAL, 1, 2);

      done_s(0) <= '1';
      wait;
    end process;

    v100_chk: process
    begin
      done_s(1) <= '0';
      vlan_ack_s(1).ready <= '0';
      wait for 100 ns;

      committed_check("demux vid 100",
                      vlan_req_s(1), vlan_ack_s(1), clock_s,
                      v100_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(1) <= '1';
      wait;
    end process;

    v200_chk: process
    begin
      done_s(2) <= '0';
      vlan_ack_s(2).ready <= '0';
      wait for 100 ns;

      committed_check("demux vid 200",
                      vlan_req_s(2), vlan_ack_s(2), clock_s,
                      v200_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(2) <= '1';
      wait;
    end process;

    dut: nsl_inet.vlan.vlan_demux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c,
        native_vlan_id_c => native_vlan_id_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => in_s.req,
        in_o => in_s.ack,

        vlan_o => vlan_req_s,
        vlan_i => vlan_ack_s
        );
  end block;

  mux: block
    signal out_s : nsl_bnoc.committed.committed_bus;
    signal vlan_req_s : nsl_bnoc.committed.committed_req_array(0 to 2);
    signal vlan_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 2);
  begin
    gen: process
    begin
      vlan_req_s(0).valid <= '0';
      vlan_req_s(1).valid <= '0';
      vlan_req_s(2).valid <= '0';
      wait for 100 ns;

      committed_put(vlan_req_s(0), vlan_ack_s(0), clock_s,
                    untagged_frame_c, true, 1, 3);
      committed_put(vlan_req_s(1), vlan_ack_s(1), clock_s,
                    v100_untagged_c, true, 1, 3);
      committed_put(vlan_req_s(2), vlan_ack_s(2), clock_s,
                    v200_untagged_c, true, 1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(3) <= '0';
      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("mux native",
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
        vlan_id_c => vlan_id_list_c,
        native_vlan_id_c => native_vlan_id_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        vlan_i => vlan_req_s,
        vlan_o => vlan_ack_s,

        out_o => out_s.req,
        out_i => out_s.ack
        );
  end block;

  -- Default native VLAN (0) is not in the VID list: untagged frames
  -- are dropped
  native_absent: block
    signal in_s : nsl_bnoc.committed.committed_bus;
    signal vlan_req_s : nsl_bnoc.committed.committed_req_array(0 to 1);
    signal vlan_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 1);
  begin
    gen: process
    begin
      in_s.req.valid <= '0';
      wait for 100 ns;

      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    v100_tagged_c, true, 1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(4) <= '0';
      vlan_ack_s(0).ready <= '0';
      vlan_ack_s(1).ready <= '0';
      wait for 100 ns;

      committed_check("native absent vid 100",
                      vlan_req_s(0), vlan_ack_s(0), clock_s,
                      v100_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(4) <= '1';
      wait;
    end process;

    dut: nsl_inet.vlan.vlan_demux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_vector'(100, 200)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => in_s.req,
        in_o => in_s.ack,

        vlan_o => vlan_req_s,
        vlan_i => vlan_ack_s
        );
  end block;

  loopback: block
    signal in_s, out_s : nsl_bnoc.committed.committed_bus;
    signal mid_req_s : nsl_bnoc.committed.committed_req_array(0 to 2);
    signal mid_ack_s : nsl_bnoc.committed.committed_ack_array(0 to 2);
  begin
    gen: process
    begin
      in_s.req.valid <= '0';
      wait for 100 ns;

      committed_put(in_s.req, in_s.ack, clock_s,
                    v100_tagged_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    untagged_frame_c, true, 1, 3);
      -- Tagged with native VID, comes back untagged
      committed_put(in_s.req, in_s.ack, clock_s,
                    v1_tagged_c, true, 1, 3);
      committed_put(in_s.req, in_s.ack, clock_s,
                    v200_tagged_pcp_c, true, 1, 3);
      wait;
    end process;

    chk: process
    begin
      done_s(5) <= '0';
      out_s.ack.ready <= '0';
      wait for 100 ns;

      committed_check("loopback vid 100",
                      out_s.req, out_s.ack, clock_s,
                      v100_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("loopback untagged",
                      out_s.req, out_s.ack, clock_s,
                      untagged_frame_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("loopback native tag removed",
                      out_s.req, out_s.ack, clock_s,
                      v1_untagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      committed_check("loopback vid 200",
                      out_s.req, out_s.ack, clock_s,
                      v200_tagged_c, true, LOG_LEVEL_FATAL, 1, 2);

      done_s(5) <= '1';
      wait;
    end process;

    demux: nsl_inet.vlan.vlan_demux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c,
        native_vlan_id_c => native_vlan_id_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => in_s.req,
        in_o => in_s.ack,

        vlan_o => mid_req_s,
        vlan_i => mid_ack_s
        );

    mux: nsl_inet.vlan.vlan_mux
      generic map(
        header_length_c => 0,
        vlan_id_c => vlan_id_list_c,
        native_vlan_id_c => native_vlan_id_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        vlan_i => mid_req_s,
        vlan_o => mid_ack_s,

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
