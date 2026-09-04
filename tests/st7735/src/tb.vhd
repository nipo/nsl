library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sitronix, nsl_spi, nsl_color, nsl_data, nsl_simulation;
use nsl_sitronix.st7735.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;

entity tb is
end entity;

architecture sim of tb is

  -- Scaled down so that millisecond sleep delays stay short in cycle
  -- count
  constant clock_hz_c : natural := 1_000_000;
  constant spi_hz_c : natural := 500_000;
  constant clock_period_c : time := 1 us;

  constant width_c : natural := 160;
  constant height_c : natural := 80;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal enable_s : std_ulogic := '1';
  signal spi_s : nsl_spi.spi.spi_slave_i;
  signal dc_s, panel_reset_n_s : std_ulogic;

  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;

  signal x_s : natural range 0 to width_c := 0;
  signal y_s : natural range 0 to height_c - 1 := 0;
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

  dut: st7735_spi_driver
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

    procedure expect_setup(constant msg: string) is
    begin
      expect(cmd_caset, '0', msg & " caset");
      expect(x"00", '1', msg & " column start msb");
      expect(x"01", '1', msg & " column start lsb");
      expect(x"00", '1', msg & " column end msb");
      expect(x"a0", '1', msg & " column end lsb");
      expect(cmd_raset, '0', msg & " raset");
      expect(x"00", '1', msg & " row start msb");
      expect(x"1a", '1', msg & " row start lsb");
      expect(x"00", '1', msg & " row end msb");
      expect(x"69", '1', msg & " row end lsb");
      expect(cmd_ramwr, '0', msg & " ramwr");
    end procedure;

    variable c: rgb24;
  begin
    -- Reset must be released before any command
    wait until panel_reset_n_s = '1';

    expect(cmd_slpout, '0', "sleep out");
    expect(cmd_colmod, '0', "colmod");
    expect(cmd_colmod_16bpp, '1', "colmod value");
    expect(cmd_madctl, '0', "madctl");
    expect(x"68", '1', "madctl value");
    expect(cmd_invon, '0', "inversion on");

    expect_setup("frame 1");
    for y in 0 to height_c - 1 loop
      for x in 0 to width_c - 1 loop
        c := pattern(x, y);
        expect(rgb565_msb(c), '1', "pixel msb "
               & integer'image(x) & "," & integer'image(y));
        expect(rgb565_lsb(c), '1', "pixel lsb "
               & integer'image(x) & "," & integer'image(y));
      end loop;
    end loop;

    -- Display on only comes after a first full frame
    expect(cmd_dispon, '0', "display on");

    -- Second frame starts on its own with refresh_i tied.  Disabling
    -- mid-frame must let the frame complete first.
    expect(cmd_caset, '0', "frame 2 caset");
    enable_s <= '0';
    expect(x"00", '1', "frame 2 column start msb");
    expect(x"01", '1', "frame 2 column start lsb");
    expect(x"00", '1', "frame 2 column end msb");
    expect(x"a0", '1', "frame 2 column end lsb");
    expect(cmd_raset, '0', "frame 2 raset");
    expect(x"00", '1', "frame 2 row start msb");
    expect(x"1a", '1', "frame 2 row start lsb");
    expect(x"00", '1', "frame 2 row end msb");
    expect(x"69", '1', "frame 2 row end lsb");
    expect(cmd_ramwr, '0', "frame 2 ramwr");
    for y in 0 to height_c - 1 loop
      for x in 0 to width_c - 1 loop
        c := pattern(x, y);
        expect(rgb565_msb(c), '1', "frame 2 pixel msb");
        expect(rgb565_lsb(c), '1', "frame 2 pixel lsb");
      end loop;
    end loop;

    -- Power-down ordering: display off, sleep in, then reset asserted
    expect(cmd_dispoff, '0', "display off");
    expect(cmd_slpin, '0', "sleep in");
    wait until panel_reset_n_s = '0';

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
