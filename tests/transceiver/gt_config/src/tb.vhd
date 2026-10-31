library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- The configuration packages turn a line rate into the multiplier,
-- divider and width settings a GT primitive is built with. Nothing
-- downstream can tell a wrong answer from a right one: a lane
-- configured for the wrong divider comes up and runs at the wrong
-- rate. The search is pure arithmetic over a vendor's divider table,
-- so what it answers is checkable here.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);


  -- Line rates the library is expected to serve, against the
  -- reference clocks a board plausibly carries. SGMII and 1000BASE-X
  -- sit at 1250, the CUFF links above that.
  type rate_case_t is
  record
    line_rate_mbps : natural;
    ref_clock_mhz : natural;
    target_vco_mhz : natural;
  end record;

  type rate_case_vector is array (natural range <>) of rate_case_t;

  constant gtpe2_rates_c : rate_case_vector := (
    (1250, 125, 2500),
    (1250, 100, 2500),
    (2500, 125, 2500),
    (2500, 100, 2500),
    (3125, 125, 3125),
    (5000, 125, 2500),
    (5000, 100, 2500),
    (6250, 125, 3125)
    );

  -- The CPLL tops out well short of the quad PLL, and this backend
  -- only drives the CPLL, so the rates above 6250 a GTHE4 quad can
  -- otherwise reach are deliberately absent.
  constant gthe4_rates_c : rate_case_vector := (
    (1250, 125, 2500),
    (2500, 125, 2500),
    (3125, 125, 3125),
    (5000, 125, 2500),
    (5000, 100, 2500),
    (6250, 125, 3125)
    );

begin

  gtpe2_config: block
  begin

    check: process
      constant ctxt : log_context := "gtpe2 config";

      -- The PLL output the primitive is left running at, from the
      -- settings the search returned. Reproducing it from the
      -- multipliers is the only way to tell a converged search from
      -- one that merely returned something in range.
      function line_rate_of(cfg : nsl_transceiver.transceiver_config_gtpe2.pll_mult_div_t;
                            ref_clock_mhz : natural) return real
      is
        variable vco_v : real;
      begin
        vco_v := real(ref_clock_mhz) * real(cfg.N1) * real(cfg.N2) / real(cfg.M);
        return 2.0 * vco_v / real(cfg.D);
      end function;

      function loopback_of(mode : nsl_transceiver.lane.loopback_mode_t)
        return std_logic_vector
      is
      begin
        return nsl_transceiver.transceiver_config_gtpe2.loopback_configure(mode);
      end function;

      variable cfg_v : nsl_transceiver.transceiver_config_gtpe2.pll_mult_div_t;
      variable width_v : nsl_transceiver.transceiver_config_gtpe2.data_width_t;
      variable rate_v, vco_v : real;
    begin
      done_s(0) <= '0';

      for i in gtpe2_rates_c'range loop
        cfg_v := nsl_transceiver.transceiver_config_gtpe2.pll_mult_div_assign(
          gtpe2_rates_c(i).line_rate_mbps,
          gtpe2_rates_c(i).target_vco_mhz,
          gtpe2_rates_c(i).ref_clock_mhz);

        rate_v := line_rate_of(cfg_v, gtpe2_rates_c(i).ref_clock_mhz);
        vco_v := rate_v * real(cfg_v.D) / 2.0;

        -- A line rate is a line rate: the dividers either reproduce
        -- the one that was asked for or the lane runs at the wrong
        -- speed.
        assert abs(rate_v - real(gtpe2_rates_c(i).line_rate_mbps)) < 1.0
          report "gtpe2 config: " & integer'image(gtpe2_rates_c(i).line_rate_mbps)
          & " Mbps off " & integer'image(gtpe2_rates_c(i).ref_clock_mhz)
          & " MHz came back as " & real'image(rate_v) & " Mbps"
          severity failure;

        -- UG482 Table 2-7: outside this window the PLL does not lock
        -- at all, and the search is the only thing standing between
        -- a configuration and that outcome.
        assert vco_v >= 1600.0 and vco_v <= 3300.0
          report "gtpe2 config: " & integer'image(gtpe2_rates_c(i).line_rate_mbps)
          & " Mbps put the vco at " & real'image(vco_v) & " MHz"
          severity failure;
      end loop;

      log_info(ctxt, "resolved " & integer'image(gtpe2_rates_c'length)
               & " line rates onto the pll divider table");

      -- The interface width decides how many bytes a lane carries
      -- per cycle, so a lane that asks for more bytes than the
      -- interface holds would drop the rest.
      for byte_count in 1 to 4 loop
        width_v := nsl_transceiver.transceiver_config_gtpe2.determine_data_width(byte_count);
        assert width_v.interface_width >= byte_count * 8
          report "gtpe2 config: a " & integer'image(byte_count)
          & " byte lane was given a " & integer'image(width_v.interface_width)
          & " bit interface"
          severity failure;
        assert width_v.internal_width = width_v.interface_width * 10 / 8
          report "gtpe2 config: a " & integer'image(width_v.interface_width)
          & " bit interface was given a " & integer'image(width_v.internal_width)
          & " bit internal width, which is not its 8b/10b expansion"
          severity failure;
      end loop;

      log_info(ctxt, "sized the interface for one to four byte lanes");

      -- Each loopback mode has to reach the primitive as its own
      -- encoding: two that collided would make a lane loop back
      -- somewhere other than where it was asked to.
      -- Table 2-27 UG482. A mode that reached the primitive as another one's
      -- encoding would loop the lane back somewhere other than
      -- where it was asked to, which looks exactly like a link that
      -- works.
      assert_equal(ctxt, "loopback off",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NONE),
                   "000", FAILURE);
      assert_equal(ctxt, "near end pma loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA),
                   "010", FAILURE);
      assert_equal(ctxt, "near end pcs loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS),
                   "001", FAILURE);
      assert_equal(ctxt, "far end pma loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_FAR_END_PMA),
                   "100", FAILURE);
      assert_equal(ctxt, "far end pcs loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_FAR_END_PCS),
                   "110", FAILURE);

      log_info(ctxt, "encoded every loopback mode as documented");

      done_s(0) <= '1';
      wait;
    end process;

  end block;

  gthe4_config: block
  begin

    check: process
      constant ctxt : log_context := "gthe4 config";

      function line_rate_of(cfg : nsl_transceiver.transceiver_config_gthe4.pll_mult_div_t;
                            ref_clock_mhz : natural) return real
      is
        variable vco_v : real;
      begin
        vco_v := real(ref_clock_mhz) * real(cfg.N1) * real(cfg.N2) / real(cfg.M);
        return 2.0 * vco_v / real(cfg.D);
      end function;

      function loopback_of(mode : nsl_transceiver.lane.loopback_mode_t)
        return std_logic_vector
      is
      begin
        return nsl_transceiver.transceiver_config_gthe4.loopback_configure(mode);
      end function;

      variable cfg_v : nsl_transceiver.transceiver_config_gthe4.pll_mult_div_t;
      variable width_v : nsl_transceiver.transceiver_config_gthe4.data_width_t;
      variable rate_v, vco_v : real;
    begin
      done_s(1) <= '0';

      for i in gthe4_rates_c'range loop
        cfg_v := nsl_transceiver.transceiver_config_gthe4.pll_mult_div_assign(
          gthe4_rates_c(i).line_rate_mbps,
          gthe4_rates_c(i).target_vco_mhz,
          gthe4_rates_c(i).ref_clock_mhz);

        rate_v := line_rate_of(cfg_v, gthe4_rates_c(i).ref_clock_mhz);
        vco_v := rate_v * real(cfg_v.D) / 2.0;

        -- The reference clocks are not all integer divisors of the
        -- rates they serve, so a rate is close enough when it lands
        -- inside the 100 ppm an 8b/10b receiver tracks.
        assert abs(rate_v - real(gthe4_rates_c(i).line_rate_mbps))
          < real(gthe4_rates_c(i).line_rate_mbps) * 1.0e-4
          report "gthe4 config: " & integer'image(gthe4_rates_c(i).line_rate_mbps)
          & " Mbps off " & integer'image(gthe4_rates_c(i).ref_clock_mhz)
          & " MHz came back as " & real'image(rate_v) & " Mbps"
          severity failure;

        -- UG576 Table 2-7.
        assert vco_v >= 2000.0 and vco_v <= 6250.0
          report "gthe4 config: " & integer'image(gthe4_rates_c(i).line_rate_mbps)
          & " Mbps put the vco at " & real'image(vco_v) & " MHz"
          severity failure;
      end loop;

      log_info(ctxt, "resolved " & integer'image(gthe4_rates_c'length)
               & " line rates onto the cpll divider table");

      for byte_count in 1 to 8 loop
        width_v := nsl_transceiver.transceiver_config_gthe4.determine_data_width(byte_count);
        assert width_v.interface_width >= byte_count * 8
          report "gthe4 config: a " & integer'image(byte_count)
          & " byte lane was given a " & integer'image(width_v.interface_width)
          & " bit interface"
          severity failure;
        assert width_v.internal_width = width_v.interface_width * 10 / 8
          report "gthe4 config: a " & integer'image(width_v.interface_width)
          & " bit interface was given a " & integer'image(width_v.internal_width)
          & " bit internal width, which is not its 8b/10b expansion"
          severity failure;

        -- The interface clock is divided down from PROGDIV, so a
        -- divider the primitive does not have is a lane with no
        -- clock. The function asserts on its own if the ratio does
        -- not land on one.
        assert nsl_transceiver.transceiver_config_gthe4.prog_div_assign(
          nsl_transceiver.transceiver_config_gthe4.pll_mult_div_assign(5000, 2500, 125),
          width_v) > 0.0
          report "gthe4 config: a " & integer'image(width_v.interface_width)
          & " bit interface got no programmable divider"
          severity failure;
      end loop;

      log_info(ctxt, "sized the interface and its divider for one to eight byte lanes");

      -- Table 2-36 UG576. A mode that reached the primitive as another one's
      -- encoding would loop the lane back somewhere other than
      -- where it was asked to, which looks exactly like a link that
      -- works.
      assert_equal(ctxt, "loopback off",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NONE),
                   "000", FAILURE);
      assert_equal(ctxt, "near end pma loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA),
                   "010", FAILURE);
      assert_equal(ctxt, "near end pcs loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS),
                   "001", FAILURE);
      assert_equal(ctxt, "far end pma loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_FAR_END_PMA),
                   "100", FAILURE);
      assert_equal(ctxt, "far end pcs loopback",
                   loopback_of(nsl_transceiver.lane.LOOPBACK_FAR_END_PCS),
                   "110", FAILURE);

      log_info(ctxt, "encoded every loopback mode as documented");

      done_s(1) <= '1';
      wait;
    end process;

  end block;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 20 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
