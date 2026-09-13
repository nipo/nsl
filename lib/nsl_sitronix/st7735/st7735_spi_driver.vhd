library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_spi, nsl_data, nsl_color, nsl_video;
use work.st7735.all;
use nsl_data.bytestream.all;

entity st7735_spi_driver is
  generic(
    clock_i_hz_c : natural;
    spi_hz_c : natural := 15_000_000;

    config_c : nsl_video.pixel_stream.config_t;
    geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(160, 80);
    column_offset_c : natural := 1;
    row_offset_c : natural := 26;
    madctl_c : byte := x"68";
    invert_c : boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    refresh_i : in std_ulogic := '1';

    spi_o : out nsl_spi.spi.spi_slave_i;
    dc_o : out std_ulogic;
    reset_n_o : out std_ulogic;

    pixel_i : in nsl_video.pixel_stream.master_t;
    pixel_o : out nsl_video.pixel_stream.slave_t;

    -- Stream framing and the panel scan agree, so what is shown is
    -- what came in.
    synced_o : out std_ulogic
    );
end entity;

architecture beh of st7735_spi_driver is

  -- Serial interface timing requires tscycw >= 66ns
  constant half_bit_cycles_c : natural :=
    (clock_i_hz_c + 2 * spi_hz_c - 1) / (2 * spi_hz_c);

  -- Reset pulse, 10us minimum
  constant reset_cycles_c : natural := (clock_i_hz_c + 99_999) / 100_000;
  -- Wait after reset release and around sleep transitions, 120ms
  constant wake_cycles_c : natural := (clock_i_hz_c / 25) * 3;
  constant timer_max_c : natural := wake_cycles_c;

  function invert_command(invert: boolean) return byte is
  begin
    if invert then
      return cmd_invon;
    end if;
    return cmd_invoff;
  end function;

  constant init_bytes_c : byte_string(0 to 4) := (
    cmd_colmod, cmd_colmod_16bpp,
    cmd_madctl, madctl_c,
    invert_command(invert_c));
  constant init_dc_c : std_ulogic_vector(0 to 4) := "01010";

  constant frame_setup_c : byte_string(0 to 10) := (
    cmd_caset,
    x"00", std_ulogic_vector(to_unsigned(column_offset_c, 8)),
    x"00", std_ulogic_vector(to_unsigned(column_offset_c + geometry_c.width - 1, 8)),
    cmd_raset,
    x"00", std_ulogic_vector(to_unsigned(row_offset_c, 8)),
    x"00", std_ulogic_vector(to_unsigned(row_offset_c + geometry_c.height - 1, 8)),
    cmd_ramwr);
  constant frame_setup_dc_c : std_ulogic_vector(0 to 10) := "01111011110";

  type state_t is (
    ST_OFF,
    ST_RESET,
    ST_RESET_WAIT,
    ST_SLPOUT,
    ST_SLPOUT_WAIT,
    ST_INIT,
    ST_SOF,
    ST_SETUP,
    ST_SOL,
    ST_PIXEL,
    ST_DISPLAY_ON,
    ST_IDLE,
    ST_DISPLAY_OFF,
    ST_SLPIN,
    ST_SLPIN_WAIT
    );

  type regs_t is
  record
    state: state_t;
    timer: natural range 0 to timer_max_c;
    ptr: natural range 0 to frame_setup_c'length;
    x: natural range 0 to geometry_c.width - 1;
    y: natural range 0 to geometry_c.height - 1;
    display_on: boolean;

    shreg: std_ulogic_vector(15 downto 0);
    bits_left: natural range 0 to 16;
    div: natural range 0 to half_bit_cycles_c - 1;
    sck: std_ulogic;
    dc: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal sof_s, sol_s, ready_s, valid_s: std_ulogic;
  signal stream_pixel_s: nsl_video.pixel_stream.pixel_t;
  signal pixel_s: nsl_color.rgb.rgb24;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_OFF;
      r.timer <= 0;
      r.display_on <= false;
      r.bits_left <= 0;
      r.sck <= '0';
      r.dc <= '0';
    end if;
  end process;

  transition: process(r, enable_i, refresh_i, valid_s, pixel_s) is
  begin
    rin <= r;

    if r.bits_left /= 0 then
      -- Mode-0 serializer, data shifted on falling edge, sampled by
      -- panel on rising edge.  State logic below is suspended until
      -- current word is fully shifted out.
      if r.div /= 0 then
        rin.div <= r.div - 1;
      elsif r.sck = '0' then
        rin.sck <= '1';
        rin.div <= half_bit_cycles_c - 1;
      else
        rin.sck <= '0';
        rin.div <= half_bit_cycles_c - 1;
        rin.shreg <= r.shreg(14 downto 0) & '0';
        rin.bits_left <= r.bits_left - 1;
      end if;
    else
      case r.state is
        when ST_OFF =>
          if enable_i = '1' then
            rin.timer <= reset_cycles_c;
            rin.state <= ST_RESET;
          end if;

        when ST_RESET =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.timer <= wake_cycles_c;
            rin.state <= ST_RESET_WAIT;
          end if;

        when ST_RESET_WAIT =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.state <= ST_SLPOUT;
          end if;

        when ST_SLPOUT =>
          rin.shreg <= cmd_slpout & x"00";
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.timer <= wake_cycles_c;
          rin.state <= ST_SLPOUT_WAIT;

        when ST_SLPOUT_WAIT =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.ptr <= 0;
            rin.state <= ST_INIT;
          end if;

        when ST_INIT =>
          if r.ptr /= init_bytes_c'length then
            rin.shreg <= init_bytes_c(r.ptr) & x"00";
            rin.bits_left <= 8;
            rin.div <= half_bit_cycles_c - 1;
            rin.dc <= init_dc_c(r.ptr);
            rin.ptr <= r.ptr + 1;
          else
            rin.state <= ST_SOF;
          end if;

        when ST_SOF =>
          rin.ptr <= 0;
          rin.state <= ST_SETUP;

        when ST_SETUP =>
          if r.ptr /= frame_setup_c'length then
            rin.shreg <= frame_setup_c(r.ptr) & x"00";
            rin.bits_left <= 8;
            rin.div <= half_bit_cycles_c - 1;
            rin.dc <= frame_setup_dc_c(r.ptr);
            rin.ptr <= r.ptr + 1;
          else
            rin.y <= 0;
            rin.state <= ST_SOL;
          end if;

        when ST_SOL =>
          rin.x <= 0;
          rin.state <= ST_PIXEL;

        when ST_PIXEL =>
          if valid_s = '1' then
            rin.shreg <= std_ulogic_vector(pixel_s.r(7 downto 3))
              & std_ulogic_vector(pixel_s.g(7 downto 2))
              & std_ulogic_vector(pixel_s.b(7 downto 3));
            rin.bits_left <= 16;
            rin.div <= half_bit_cycles_c - 1;
            rin.dc <= '1';
            if r.x /= geometry_c.width - 1 then
              rin.x <= r.x + 1;
            elsif r.y /= geometry_c.height - 1 then
              rin.y <= r.y + 1;
              rin.state <= ST_SOL;
            elsif not r.display_on then
              rin.state <= ST_DISPLAY_ON;
            else
              rin.state <= ST_IDLE;
            end if;
          end if;

        when ST_DISPLAY_ON =>
          rin.shreg <= cmd_dispon & x"00";
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.display_on <= true;
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if enable_i = '0' then
            rin.state <= ST_DISPLAY_OFF;
          elsif refresh_i = '1' then
            rin.state <= ST_SOF;
          end if;

        when ST_DISPLAY_OFF =>
          rin.shreg <= cmd_dispoff & x"00";
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.display_on <= false;
          rin.state <= ST_SLPIN;

        when ST_SLPIN =>
          rin.shreg <= cmd_slpin & x"00";
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.timer <= wake_cycles_c;
          rin.state <= ST_SLPIN_WAIT;

        when ST_SLPIN_WAIT =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.state <= ST_OFF;
          end if;
      end case;
    end if;
  end process;

  moore: process(r) is
  begin
    spi_o.sck <= r.sck;
    spi_o.mosi <= r.shreg(15);
    dc_o <= r.dc;

    sof_s <= '0';
    sol_s <= '0';

    case r.state is
      when ST_SLPOUT | ST_INIT | ST_SOF | ST_SETUP | ST_SOL | ST_PIXEL
        | ST_DISPLAY_ON | ST_DISPLAY_OFF | ST_SLPIN =>
        spi_o.cs_n <= '0';
      when others =>
        if r.bits_left /= 0 then
          spi_o.cs_n <= '0';
        else
          spi_o.cs_n <= '1';
        end if;
    end case;

    case r.state is
      when ST_OFF | ST_RESET =>
        reset_n_o <= '0';
      when others =>
        reset_n_o <= '1';
    end case;

    if r.state = ST_SOF and r.bits_left = 0 then
      sof_s <= '1';
    end if;

    if r.state = ST_SOL and r.bits_left = 0 then
      sol_s <= '1';
    end if;
  end process;

  mealy: process(r) is
  begin
    if r.state = ST_PIXEL and r.bits_left = 0 then
      ready_s <= '1';
    else
      ready_s <= '0';
    end if;
  end process;

  -- The panel scan holds its serial interface when the stream has no
  -- pixel, so a late pixel costs time, not position.
  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c,
      raster_can_wait_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => pixel_i,
      in_o => pixel_o,
      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => stream_pixel_s,
      synced_o => synced_o
      );

  pixel_s <= nsl_video.pixel_stream.to_rgb24(config_c, stream_pixel_s);

end architecture;
