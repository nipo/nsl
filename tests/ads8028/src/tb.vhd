library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_ti, nsl_spi, nsl_io, nsl_simulation, nsl_math, nsl_data, nsl_amba;
use nsl_ti.ads8028.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  constant channels_c : channel_mask_t := "101101101";

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;
  signal sck_s, mosi_s, miso_s, cs_n_s : std_logic;
  signal cs_n_o_s : nsl_io.io.opendrain_vector(0 to 0);
  signal mosi_o_s : nsl_io.io.tristated;

  signal code_s : code_vector(0 to channel_count_c-1);
  signal valid_s, strobe_s : channel_mask_t;

  constant apb_config_c : nsl_amba.apb.config_t
    := nsl_amba.apb.apb3_config(address_width => 8, data_bus_width => 32,
                                ready => true, err => true);
  signal apb_m_s : nsl_amba.apb.master_t;
  signal apb_s_s : nsl_amba.apb.slave_t;

  -- Model control
  signal device_reset_s : boolean := false;
  signal writes_s : natural := 0;

  -- Value converted by the model for each channel
  function sample(channel : natural) return code_t is
  begin
    if channel = temperature_c then
      -- -10 degrees Celsius
      return x"fd8";
    end if;
    return to_unsigned(16#100# * channel + 16#5a#, 12);
  end function;

begin

  scanner: nsl_ti.ads8028.ads8028_framed_scanner
    generic map(
      channels_c => channels_c,
      slave_no_c => 0,
      divisor_c => 2,
      frame_gap_c => 10,
      resync_frames_c => 16
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      cmd_o => cmd_s.req,
      cmd_i => cmd_s.ack,
      rsp_i => rsp_s.req,
      rsp_o => rsp_s.ack,
      code_o => code_s,
      valid_o => valid_s,
      strobe_o => strobe_s
      );

  registers: nsl_ti.ads8028.ads8028_apb_registers
    generic map(
      config_c => apb_config_c,
      channels_c => channels_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      apb_i => apb_m_s,
      apb_o => apb_s_s,
      code_i => code_s,
      valid_i => valid_s,
      strobe_i => strobe_s
      );

  transactor: nsl_spi.transactor.spi_framed_transactor
    generic map(
      slave_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sck_o => sck_s,
      cs_n_o => cs_n_o_s,
      mosi_o => mosi_o_s,
      miso_i => miso_s,
      cmd_i => cmd_s.req,
      cmd_o => cmd_s.ack,
      rsp_o => rsp_s.req,
      rsp_i => rsp_s.ack
      );

  cs_n_s <= cs_n_o_s(0).drain_n;
  mosi_s <= mosi_o_s.v when mosi_o_s.en = '1' else 'Z';

  -- ADS8028 model: 16-bit frames, control register written on the
  -- first 16 SCK falling edges, address and result shifted out from the
  -- CS falling edge, conversions one frame after selection, results
  -- one frame after conversion. No temperature conversion delay.
  ads8028_model: process
    variable ctrl : std_ulogic_vector(15 downto 0) := (others => '0');
    variable din, dout : std_ulogic_vector(15 downto 0) := (others => '1');
    variable converting : integer := -1;
    variable bits : natural;
    variable started : boolean := false;

    function selected(ctrl : std_ulogic_vector(15 downto 0); channel : natural) return boolean is
    begin
      return ctrl(13 - channel) = '1';
    end function;

    function next_channel(ctrl : std_ulogic_vector(15 downto 0); prev : integer) return integer is
    begin
      for c in prev + 1 to channel_count_c - 1
      loop
        if selected(ctrl, c) then
          return c;
        end if;
      end loop;
      if ctrl(14) = '1' then
        for c in 0 to prev
        loop
          if selected(ctrl, c) then
            return c;
          end if;
        end loop;
      end if;
      return -1;
    end function;

  begin
    miso_s <= 'Z';
    if not started then
      wait until reset_n_s = '1' and cs_n_s = '1';
      started := true;
    end if;
    wait until cs_n_s = '0' or device_reset_s;
    if device_reset_s then
      ctrl := (others => '0');
      converting := -1;
      dout := (others => '1');
      wait until not device_reset_s;
    else
      miso_s <= dout(15);
      bits := 0;
      while bits < 16 and cs_n_s = '0'
      loop
        wait until falling_edge(sck_s) or cs_n_s = '1';
        exit when cs_n_s = '1';
        din := din(14 downto 0) & mosi_s;
        dout := dout(14 downto 0) & '1';
        bits := bits + 1;
        if bits < 16 then
          miso_s <= dout(15);
        else
          miso_s <= 'Z';
        end if;
      end loop;
      if cs_n_s = '0' then
        wait until cs_n_s = '1';
      end if;
      assert bits = 16
        report "ADS8028 frame of " & integer'image(bits) & " bits"
        severity failure;

      if converting >= 0 then
        if converting = temperature_c then
          dout := x"8" & std_ulogic_vector(sample(converting));
        else
          dout := std_ulogic_vector(to_unsigned(converting, 4)) & std_ulogic_vector(sample(converting));
        end if;
      else
        dout := (others => '1');
      end if;

      if din(15) = '1' then
        ctrl := din;
        writes_s <= writes_s + 1;
        converting := next_channel(ctrl, -1);
      else
        converting := next_channel(ctrl, converting);
      end if;
    end if;
  end process;

  stimulus: process
    variable strobes : natural;

    procedure check_codes(what : string) is
    begin
      for c in 0 to channel_count_c - 1
      loop
        if channels_c(c) = '1' then
          assert valid_s(c) = '1'
            report what & ": channel " & integer'image(c) & " has no result"
            severity failure;
          assert code_s(c) = sample(c)
            report what & ": channel " & integer'image(c) & " reads "
            & nsl_data.text.to_hex_string(std_ulogic_vector(code_s(c)))
            severity failure;
        else
          assert valid_s(c) = '0'
            report what & ": disabled channel " & integer'image(c) & " has a result"
            severity failure;
        end if;
      end loop;
    end procedure;

    procedure wait_scans(count : natural) is
    begin
      strobes := 0;
      while strobes < count
      loop
        wait until rising_edge(clock_s);
        if strobe_s(temperature_c) = '1' then
          strobes := strobes + 1;
        end if;
      end loop;
    end procedure;

  begin
    done_s <= "0";
    apb_m_s <= nsl_amba.apb.transfer_idle(apb_config_c);
    wait until reset_n_s = '1';

    wait_scans(4);
    check_codes("First scans");
    assert writes_s = 1
      report "Control register written " & integer'image(writes_s) & " times"
      severity failure;
    assert nsl_math.fixed.to_suv(to_celsius(code_s(temperature_c)))
      = nsl_math.fixed.to_suv(nsl_math.fixed.to_sfixed(-10.0, 9, -2))
      report "Temperature conversion"
      severity failure;
    log_info("Scanner reads every enabled channel");

    wait until falling_edge(clock_s);
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s_s, apb_m_s, 15, 2,
                           val => x"0001016d");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s_s, apb_m_s, 2, 2,
                           val => x"80" & "--------" & x"025a");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s_s, apb_m_s, 1, 2,
                           val => x"00000000");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s_s, apb_m_s, 8, 2,
                           val => x"80" & "--------" & x"0fd8");
    log_info("Registers report results and channels");

    -- Device loses its configuration: scanner resynchronizes
    device_reset_s <= true;
    wait for 1 us;
    device_reset_s <= false;
    wait_scans(4);
    check_codes("After device reset");
    assert writes_s = 2
      report "Control register written " & integer'image(writes_s) & " times"
      severity failure;
    log_info("Scanner rewrites the control register after a device reset");

    done_s <= "1";
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 32 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end architecture;
