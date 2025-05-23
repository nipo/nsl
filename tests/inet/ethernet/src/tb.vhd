library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_mii, nsl_data, nsl_inet, nsl_bnoc, nsl_clocking;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_data.text.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.rgmii.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_mii.testing.all;
use nsl_inet.ethernet.all;
use nsl_bnoc.testing.all;

entity tb is
end tb;

architecture beh of tb is

  constant dut_hwaddr_c : mac48_t := from_hex("020000000001");
  constant tester_hwaddr_c : mac48_t := from_hex("02000000feed");
  constant min_frame_size_c : natural := 64;

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal l3_dead_rx_s, l3_dead_tx_s: nsl_bnoc.committed.committed_bus;

  signal rgmii_s: rgmii_io;
  signal s_done : std_ulogic_vector(0 to 3);

  signal link_up_s, full_duplex_s: std_ulogic;
  signal speed_s : link_speed_t;

  constant frame_rx_0_c : byte_string := frame_pack(
    dut_hwaddr_c,
    tester_hwaddr_c,
    16#dead#,
    from_hex("deadbeef"));

  constant frame_rx_1_c : byte_string := frame_pack(
    dut_hwaddr_c,
    tester_hwaddr_c,
    16#dead#,
    from_hex("deadbeef"));

  constant frame_rx_2_c : byte_string := frame_pack(
    from_hex("20cf301acea1"),
    from_hex("6238e0c2bd30"),
    16#0806#,
    from_hex("00010800060400016238e0c2bd300a2a2a"
             &"010000000000000a2a2a02000000000000"
             &"000000000000000000000000"));

  constant frame_rx_3_c : byte_string := frame_pack(
    dut_hwaddr_c,
    tester_hwaddr_c,
    16#dead#,
    from_hex("decafbad"));
  
  constant frame_rx_4_c : byte_string := frame_pack(
    dut_hwaddr_c,
    tester_hwaddr_c,
    16#dead#,
    from_hex("badbadbd"));

  function as_dead(l2_frame: byte_string) return byte_string
  is
    alias f: byte_string(0 to l2_frame'length-1) is l2_frame;
  begin
    return l3_pack(f(6 to 11),
                   f(0 to 5) = from_hex("ffffffffffff"),
                   f(14 to f'right-4));
  end function;

  constant frame_tx_0_c : byte_string := from_hex(
    "02000000feed00deadbeef"
    );

  constant frame_tx_1_c : byte_string := from_hex(
    "02000000feed00deadbeef"
    );

  function from_dead(dead_frame: byte_string) return byte_string
  is
    alias f: byte_string(0 to dead_frame'length-1) is dead_frame;
    variable is_bcast: boolean := f(6) = x"01";
    variable daddr: mac48_t;
  begin
    if is_bcast then
      daddr := (others => x"ff");
    else
      daddr := tester_hwaddr_c;
    end if;

    return frame_pack(daddr, dut_hwaddr_c, 16#dead#, f(7 to f'right),
                      min_frame_size_c);
  end function;
  
begin
      
  from_network: process
  begin
    s_done(0) <= '0';

    -- Frame RX 0, OK
    rgmii_interframe_put(rgmii_s.p2m, 1024, LINK_SPEED_10);
    rgmii_frame_put(rgmii_s.p2m,
                    data => frame_rx_0_c,
                    speed => LINK_SPEED_10);

    -- Frame RX 1, should be dropped / reported bad
    rgmii_interframe_put(rgmii_s.p2m, 1024, LINK_SPEED_10);
    rgmii_frame_put(rgmii_s.p2m,
                    data => frame_rx_1_c,
                    error_at_bit => 13*8,
                    speed => LINK_SPEED_10);

    -- Frame RX 2, OK, but not for us, should be ignored
    rgmii_interframe_put(rgmii_s.p2m, 1024, LINK_SPEED_10);
    rgmii_frame_put(rgmii_s.p2m,
                    data => frame_rx_2_c,
                    speed => LINK_SPEED_10);
    rgmii_interframe_put(rgmii_s.p2m, 128, LINK_SPEED_10);

    -- Frame RX 2.5, bad frames, should not pass through
    rgmii_interframe_put(rgmii_s.p2m, 2048, LINK_SPEED_1000);
    for i in 1 to 6+6+2+4+8
    loop
      rgmii_interframe_put(rgmii_s.p2m, 48, LINK_SPEED_1000);
      rgmii_frame_put(rgmii_s.p2m,
                      data => byte_string'(1 to i => x"02"),
                      speed => LINK_SPEED_1000);
    end loop;

    -- Frame RX 3, OK
    rgmii_interframe_put(rgmii_s.p2m, 2048, LINK_SPEED_1000);
    rgmii_frame_put(rgmii_s.p2m,
                    data => frame_rx_3_c,
                    speed => LINK_SPEED_1000);
    rgmii_interframe_put(rgmii_s.p2m, 128, LINK_SPEED_1000);

    -- Frame RX 4,
    rgmii_interframe_put(rgmii_s.p2m, 2048, LINK_SPEED_100);
    rgmii_frame_put(rgmii_s.p2m,
                    data => frame_rx_4_c,
                    speed => LINK_SPEED_100);

    while s_done(3) = '0'
    loop
      rgmii_interframe_put(rgmii_s.p2m, 1024,
                           speed => LINK_SPEED_100);
    end loop;

    s_done(0) <= '1';
    wait;
  end process;

  to_l3_dead: process
    variable frame: byte_stream;
    variable valid: boolean;
  begin
    s_done(1) <= '0';
    l3_dead_rx_s.ack.ready <= '0';
    wait for 1 us;

    -- Frame RX 0, OK
    committed_check("DEAD0",
                    l3_dead_rx_s.req, l3_dead_rx_s.ack, s_clk,
                    as_dead(frame_rx_0_c), true,
                    LOG_LEVEL_FATAL);

    assert speed_s = LINK_SPEED_10
      report "Bad reported speed"
      severity failure;

    -- Frame RX 3, OK
    committed_check("DEAD0",
                    l3_dead_rx_s.req, l3_dead_rx_s.ack, s_clk,
                    as_dead(frame_rx_3_c), true,
                    LOG_LEVEL_FATAL);
    assert speed_s = LINK_SPEED_1000
      report "Bad reported speed: " & to_string(speed_s)
      severity failure;

    -- Frame RX 4, OK
    committed_check("DEAD0",
                    l3_dead_rx_s.req, l3_dead_rx_s.ack, s_clk,
                    as_dead(frame_rx_4_c), true,
                    LOG_LEVEL_FATAL);
    assert speed_s = LINK_SPEED_100
      report "Bad reported speed: " & to_string(speed_s)
      severity failure;

    s_done(1) <= '1';
    wait;
  end process;

  from_l3_dead: process
  begin
    s_done(2) <= '0';
    l3_dead_tx_s.req.valid <= '0';

    wait until s_done(1) = '1';

    log_info("Starting to send outbound frames");

    -- Frame TX 0
    committed_put(l3_dead_tx_s.req, l3_dead_tx_s.ack, s_clk,
                  frame_tx_0_c, true);

    -- Frame TX 1
    committed_put(l3_dead_tx_s.req, l3_dead_tx_s.ack, s_clk,
                  frame_tx_1_c, true);

    committed_wait(l3_dead_tx_s.req, l3_dead_tx_s.ack, s_clk, 2048);

    s_done(2) <= '1';
    wait;
  end process;

  to_network: process
  begin
    s_done(3) <= '0';

    wait until s_done(1) = '1';

    -- Frame TX 0
    rgmii_frame_check("TX 0", rgmii_s.m2p,
                      from_dead(frame_tx_0_c), true,
                      LINK_SPEED_100, LOG_LEVEL_FATAL);

    -- Frame TX 1
    rgmii_frame_check("TX 1", rgmii_s.m2p,
                      from_dead(frame_tx_1_c), true,
                      LINK_SPEED_100, LOG_LEVEL_FATAL);

    s_done(3) <= '1';
    wait;
  end process;

  dut_inst: work.root.dut
    generic map(
      hwaddr_c => dut_hwaddr_c
      )
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn_async,

      phy_o => rgmii_s.m2p,
      phy_i => rgmii_s.p2m,

      speed_o => speed_s,
      link_up_o => link_up_s,
      full_duplex_o => full_duplex_s,
      
      l3_dead_rx_o => l3_dead_rx_s.req,
      l3_dead_rx_i => l3_dead_rx_s.ack,
      l3_dead_tx_i => l3_dead_tx_s.req,
      l3_dead_tx_o => l3_dead_tx_s.ack
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
