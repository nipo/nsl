library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_altera, nsl_simulation, nsl_amba, nsl_data;
use nsl_data.text.all;

-- A flat AXI master, standing for the HPS, goes through a master port,
-- a slave port and another master port to a RAM.  While in reset, the
-- master pulses its valid signals as the lightweight bridge does at
-- bring-up: nothing may be accepted nor answered.  Then words are
-- written and read back, single and in bursts.
entity tb is
end tb;

architecture arch of tb is

  constant config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 16, data_bus_width => 32,
                               id_width => 4, max_length => 16, size => true,
                               burst => true, cache => true, lock => true);

  subtype addr_t is std_logic_vector(15 downto 0);
  subtype data_t is std_logic_vector(31 downto 0);
  subtype id_t is std_logic_vector(3 downto 0);

  type flat_t is
  record
    awid, arid, bid, rid : id_t;
    awaddr, araddr : addr_t;
    awlen, arlen : std_logic_vector(7 downto 0);
    awsize, arsize, awprot, arprot : std_logic_vector(2 downto 0);
    awburst, arburst, bresp, rresp : std_logic_vector(1 downto 0);
    awlock, arlock : std_logic;
    awcache, arcache : std_logic_vector(3 downto 0);
    awuser, aruser : std_logic_vector(7 downto 0);
    wdata, rdata : data_t;
    wstrb : std_logic_vector(3 downto 0);
    wlast, rlast : std_logic;
    awvalid, awready, wvalid, wready, bvalid, bready : std_logic;
    arvalid, arready, rvalid, rready : std_logic;
  end record;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal hps_s, mid_s : flat_t;
  signal m0_reset_n_s, s_reset_n_s, m1_reset_n_s : std_ulogic;
  signal m0_m_s, m1_m_s : nsl_amba.axi4_mm.master_t;
  signal m0_s_s, m1_s_s : nsl_amba.axi4_mm.slave_t;

  function word(n: natural) return data_t is
  begin
    return std_logic_vector(to_unsigned(16#5a000000# + n * 16#010203#, 32));
  end function;

begin

  hps: process
    -- Signals read right after the edge hold the values the edge
    -- sampled: a handshake is seen in the cycle it occurs.
    procedure cycle is
    begin
      wait until rising_edge(clock_s);
    end procedure;

    procedure write(addr: natural; len: natural; first: natural) is
    begin
      hps_s.awaddr <= std_logic_vector(to_unsigned(addr, 16));
      hps_s.awlen <= std_logic_vector(to_unsigned(len - 1, 8));
      hps_s.awid <= x"3";
      hps_s.awvalid <= '1';
      loop
        cycle;
        exit when hps_s.awready = '1';
      end loop;
      hps_s.awvalid <= '0';
      for i in 0 to len - 1
      loop
        hps_s.wdata <= word(first + i);
        hps_s.wlast <= '0';
        if i = len - 1 then
          hps_s.wlast <= '1';
        end if;
        hps_s.wvalid <= '1';
        loop
          cycle;
          exit when hps_s.wready = '1';
        end loop;
      end loop;
      hps_s.wvalid <= '0';
      hps_s.bready <= '1';
      loop
        cycle;
        exit when hps_s.bvalid = '1';
      end loop;
      assert hps_s.bid = x"3" and hps_s.bresp = "00"
        report "Bad write response" severity failure;
      hps_s.bready <= '0';
    end procedure;

    procedure read(addr: natural; len: natural; first: natural) is
    begin
      hps_s.araddr <= std_logic_vector(to_unsigned(addr, 16));
      hps_s.arlen <= std_logic_vector(to_unsigned(len - 1, 8));
      hps_s.arid <= x"5";
      hps_s.arvalid <= '1';
      loop
        cycle;
        exit when hps_s.arready = '1';
      end loop;
      hps_s.arvalid <= '0';
      hps_s.rready <= '1';
      for i in 0 to len - 1
      loop
        loop
          cycle;
          exit when hps_s.rvalid = '1';
        end loop;
        assert hps_s.rdata = word(first + i)
          report "Read " & to_hex_string(hps_s.rdata) & " at beat " & integer'image(i)
          & ", expected " & to_hex_string(word(first + i))
          severity failure;
        assert hps_s.rid = x"5" and hps_s.rresp = "00"
          report "Bad read response" severity failure;
        assert (hps_s.rlast = '1') = (i = len - 1)
          report "Bad rlast" severity failure;
      end loop;
      hps_s.rready <= '0';
    end procedure;

  begin
    done_s(0) <= '0';
    hps_s.awsize <= "010";
    hps_s.arsize <= "010";
    hps_s.awburst <= "01";
    hps_s.arburst <= "01";
    hps_s.awlock <= '0';
    hps_s.arlock <= '0';
    hps_s.awcache <= "0000";
    hps_s.arcache <= "0000";
    hps_s.awprot <= "000";
    hps_s.arprot <= "000";
    hps_s.awid <= x"0";
    hps_s.arid <= x"0";
    hps_s.awaddr <= (others => '0');
    hps_s.araddr <= (others => '0');
    hps_s.awlen <= x"00";
    hps_s.arlen <= x"00";
    hps_s.wdata <= x"deadc0de";
    hps_s.wstrb <= "1111";
    hps_s.wlast <= '1';
    hps_s.awvalid <= '0';
    hps_s.wvalid <= '0';
    hps_s.bready <= '0';
    hps_s.arvalid <= '0';
    hps_s.rready <= '0';

    -- The bring-up pulses, while in reset.
    wait until reset_n_s = '0';
    for i in 1 to 4
    loop
      cycle;
    end loop;
    hps_s.arvalid <= '1';
    hps_s.awvalid <= '1';
    hps_s.wvalid <= '1';
    hps_s.rready <= '1';
    hps_s.bready <= '1';
    cycle;
    hps_s.arvalid <= '0';
    hps_s.awvalid <= '0';
    hps_s.wvalid <= '0';
    cycle;
    hps_s.rready <= '0';
    hps_s.bready <= '0';

    wait until reset_n_s = '1';
    for i in 1 to 10
    loop
      cycle;
    end loop;

    report "Writing" severity note;
    write(16#10#, 1, 0);
    write(16#20#, 4, 1);
    write(16#14#, 1, 5);
    report "Reading" severity note;
    read(16#10#, 1, 0);
    read(16#20#, 4, 1);
    read(16#14#, 1, 5);
    read(16#24#, 3, 2);
    report "Pass" severity note;
    done_s(0) <= '1';
    wait;
  end process;

  watchdog: process
  begin
    wait for 100 us;
    assert done_s(0) = '1' report "Timeout" severity failure;
    wait;
  end process;

  -- Nothing may be answered, but what is asked after reset.
  monitor: process(clock_s)
  begin
    if rising_edge(clock_s) then
      if m0_reset_n_s = '0' then
        assert hps_s.arready = '0' and hps_s.awready = '0' and hps_s.wready = '0'
          and hps_s.rvalid = '0' and hps_s.bvalid = '0'
          report "Handshake in reset" severity failure;
        assert m0_m_s.ar.valid = '0' and m0_m_s.aw.valid = '0' and m0_m_s.w.valid = '0'
          report "Request in reset" severity failure;
      end if;
      if hps_s.arvalid = '0' and hps_s.rready = '0' then
        assert hps_s.rvalid = '0' report "Spurious read response" severity failure;
      end if;
    end if;
  end process;

  m0: nsl_altera.hps.hps_pd_master_port
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      reset_n_o => m0_reset_n_s,

      awid => hps_s.awid,
      awaddr => hps_s.awaddr,
      awlen => hps_s.awlen,
      awsize => hps_s.awsize,
      awburst => hps_s.awburst,
      awlock => hps_s.awlock,
      awcache => hps_s.awcache,
      awprot => hps_s.awprot,
      awvalid => hps_s.awvalid,
      awready => hps_s.awready,
      wdata => hps_s.wdata,
      wstrb => hps_s.wstrb,
      wlast => hps_s.wlast,
      wvalid => hps_s.wvalid,
      wready => hps_s.wready,
      bid => hps_s.bid,
      bresp => hps_s.bresp,
      bvalid => hps_s.bvalid,
      bready => hps_s.bready,
      arid => hps_s.arid,
      araddr => hps_s.araddr,
      arlen => hps_s.arlen,
      arsize => hps_s.arsize,
      arburst => hps_s.arburst,
      arlock => hps_s.arlock,
      arcache => hps_s.arcache,
      arprot => hps_s.arprot,
      arvalid => hps_s.arvalid,
      arready => hps_s.arready,
      rid => hps_s.rid,
      rdata => hps_s.rdata,
      rresp => hps_s.rresp,
      rlast => hps_s.rlast,
      rvalid => hps_s.rvalid,
      rready => hps_s.rready,

      axi_o => m0_m_s,
      axi_i => m0_s_s
      );

  s: nsl_altera.hps.hps_pd_slave_port
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => m0_reset_n_s,
      reset_n_o => s_reset_n_s,

      axi_i => m0_m_s,
      axi_o => m0_s_s,

      awid => mid_s.awid,
      awaddr => mid_s.awaddr,
      awlen => mid_s.awlen,
      awsize => mid_s.awsize,
      awburst => mid_s.awburst,
      awlock => mid_s.awlock,
      awcache => mid_s.awcache,
      awprot => mid_s.awprot,
      awuser => mid_s.awuser,
      awvalid => mid_s.awvalid,
      awready => mid_s.awready,
      wdata => mid_s.wdata,
      wstrb => mid_s.wstrb,
      wlast => mid_s.wlast,
      wvalid => mid_s.wvalid,
      wready => mid_s.wready,
      bid => mid_s.bid,
      bresp => mid_s.bresp,
      bvalid => mid_s.bvalid,
      bready => mid_s.bready,
      arid => mid_s.arid,
      araddr => mid_s.araddr,
      arlen => mid_s.arlen,
      arsize => mid_s.arsize,
      arburst => mid_s.arburst,
      arlock => mid_s.arlock,
      arcache => mid_s.arcache,
      arprot => mid_s.arprot,
      aruser => mid_s.aruser,
      arvalid => mid_s.arvalid,
      arready => mid_s.arready,
      rid => mid_s.rid,
      rdata => mid_s.rdata,
      rresp => mid_s.rresp,
      rlast => mid_s.rlast,
      rvalid => mid_s.rvalid,
      rready => mid_s.rready
      );

  m1: nsl_altera.hps.hps_pd_master_port
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => s_reset_n_s,
      reset_n_o => m1_reset_n_s,

      awid => mid_s.awid,
      awaddr => mid_s.awaddr,
      awlen => mid_s.awlen,
      awsize => mid_s.awsize,
      awburst => mid_s.awburst,
      awlock => mid_s.awlock,
      awcache => mid_s.awcache,
      awprot => mid_s.awprot,
      awvalid => mid_s.awvalid,
      awready => mid_s.awready,
      wdata => mid_s.wdata,
      wstrb => mid_s.wstrb,
      wlast => mid_s.wlast,
      wvalid => mid_s.wvalid,
      wready => mid_s.wready,
      bid => mid_s.bid,
      bresp => mid_s.bresp,
      bvalid => mid_s.bvalid,
      bready => mid_s.bready,
      arid => mid_s.arid,
      araddr => mid_s.araddr,
      arlen => mid_s.arlen,
      arsize => mid_s.arsize,
      arburst => mid_s.arburst,
      arlock => mid_s.arlock,
      arcache => mid_s.arcache,
      arprot => mid_s.arprot,
      arvalid => mid_s.arvalid,
      arready => mid_s.arready,
      rid => mid_s.rid,
      rdata => mid_s.rdata,
      rresp => mid_s.rresp,
      rlast => mid_s.rlast,
      rvalid => mid_s.rvalid,
      rready => mid_s.rready,

      axi_o => m1_m_s,
      axi_i => m1_s_s
      );

  ram: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => m1_reset_n_s,
      axi_i => m1_m_s,
      axi_o => m1_s_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 200 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
