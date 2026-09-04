library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_solomonsystech, nsl_spi, nsl_color, nsl_data, nsl_simulation;
use nsl_solomonsystech.ssd1331.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;

entity tb is
end entity;

architecture sim of tb is

  -- Scaled down so that millisecond power sequencing delays stay short
  -- in cycle count
  constant clock_hz_c : natural := 1_000_000;
  constant spi_hz_c : natural := 250_000;
  constant clock_period_c : time := 1 us;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal enable_s : std_ulogic := '1';
  signal spi_s : nsl_spi.spi.spi_slave_i;
  signal dc_s, panel_reset_n_s, vcc_en_s, power_en_s : std_ulogic;

  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal x_s : natural range 0 to max_width_c := 0;
  signal y_s : natural range 0 to max_height_c - 1 := 0;
  signal first_line_s : boolean := true;
  signal valid_phase_s : natural range 0 to 6 := 0;

  signal done_s : boolean := false;

  function pattern(x, y: natural) return rgb24 is
  begin
    return (r => to_unsigned((x * 2) mod 256, 8),
            g => to_unsigned((y * 4) mod 256, 8),
            b => to_unsigned((x + y) mod 256, 8));
  end function;

  function rgb565_msb(c: rgb24) return byte is
  begin
    return std_ulogic_vector(c.r(7 downto 3)) & std_ulogic_vector(c.g(7 downto 5));
  end function;

  function rgb565_lsb(c: rgb24) return byte is
  begin
    return std_ulogic_vector(c.g(4 downto 2)) & std_ulogic_vector(c.b(7 downto 3));
  end function;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: ssd1331_spi_driver
    generic map(
      clock_i_hz_c => clock_hz_c,
      spi_hz_c => spi_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      enable_i => enable_s,
      refresh_i => '1',

      spi_o => spi_s,
      dc_o => dc_s,
      reset_n_o => panel_reset_n_s,
      vcc_en_o => vcc_en_s,
      power_en_o => power_en_s,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s
      );

  -- Frame generator model, follows sof/sol/ready strobes and exercises
  -- backpressure through pixel_valid_i
  source: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      valid_phase_s <= (valid_phase_s + 1) mod 7;

      if sof_s = '1' then
        first_line_s <= true;
      end if;

      if sol_s = '1' then
        x_s <= 0;
        if first_line_s then
          y_s <= 0;
          first_line_s <= false;
        else
          y_s <= y_s + 1;
        end if;
      elsif pixel_ready_s = '1' then
        x_s <= x_s + 1;
      end if;
    end if;
  end process;

  pixel_s <= pattern(x_s, y_s);
  pixel_valid_s <= '0' when valid_phase_s < 2 else '1';

  monitor: process is
    procedure expect(constant v: byte;
                     constant dc: std_ulogic;
                     constant msg: string) is
      variable sh: byte;
    begin
      for i in 0 to 7 loop
        wait until rising_edge(spi_s.sck);
        assert spi_s.cs_n = '0'
          report msg & ": CS released mid-byte"
          severity failure;
        sh := sh(6 downto 0) & spi_s.mosi;
      end loop;
      assert dc_s = dc
        report msg & ": bad D/C"
        severity failure;
      assert sh = v
        report msg & ": expected " & integer'image(to_integer(unsigned(v)))
        & ", got " & integer'image(to_integer(unsigned(sh)))
        severity failure;
    end procedure;

    procedure expect_frame(constant msg: string) is
      variable c: rgb24;
    begin
      expect(cmd_column_setup, '0', msg & " column setup");
      expect(x"00", '0', msg & " column start");
      expect(x"5f", '0', msg & " column end");
      expect(cmd_row_setup, '0', msg & " row setup");
      expect(x"00", '0', msg & " row start");
      expect(x"3f", '0', msg & " row end");

      for y in 0 to max_height_c - 1 loop
        for x in 0 to max_width_c - 1 loop
          c := pattern(x, y);
          expect(rgb565_msb(c), '1', msg & " pixel msb "
                 & integer'image(x) & "," & integer'image(y));
          expect(rgb565_lsb(c), '1', msg & " pixel lsb "
                 & integer'image(x) & "," & integer'image(y));
        end loop;
      end loop;
    end procedure;
  begin
    -- Power-up ordering
    wait until power_en_s = '1';
    assert vcc_en_s = '0' and panel_reset_n_s = '0'
      report "Vcc or reset asserted at power-up"
      severity failure;
    wait until panel_reset_n_s = '1';
    assert vcc_en_s = '0'
      report "Vcc enabled before reset release"
      severity failure;
    wait until vcc_en_s = '1';

    for i in init_sequence_c'range loop
      expect(init_sequence_c(i), '0', "init byte " & integer'image(i));
    end loop;

    -- Display on only comes after a first full frame
    expect_frame("frame 1");
    expect(cmd_display_on_normal, '0', "display on");

    -- Second frame starts on its own with refresh_i tied.  Disabling
    -- mid-frame must let the frame complete first.
    expect(cmd_column_setup, '0', "frame 2 column setup");
    enable_s <= '0';
    expect(x"00", '0', "frame 2 column start");
    expect(x"5f", '0', "frame 2 column end");
    expect(cmd_row_setup, '0', "frame 2 row setup");
    expect(x"00", '0', "frame 2 row start");
    expect(x"3f", '0', "frame 2 row end");
    for y in 0 to max_height_c - 1 loop
      for x in 0 to max_width_c - 1 loop
        expect(rgb565_msb(pattern(x, y)), '1', "frame 2 pixel msb");
        expect(rgb565_lsb(pattern(x, y)), '1', "frame 2 pixel lsb");
      end loop;
    end loop;

    -- Power-down ordering
    expect(cmd_display_sleep, '0', "display sleep");
    wait until vcc_en_s = '0';
    assert power_en_s = '1'
      report "Logic supply cut before Vcc"
      severity failure;
    wait until power_en_s = '0';

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 sec;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
