library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity pixel_stream_requester is
  generic(
    geometry_c: nsl_video.mode.geometry_t;
    config_c: nsl_video.pixel_stream.config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    enable_i: in std_ulogic := '1';

    sof_o: out std_ulogic;
    sol_o: out std_ulogic;
    ready_o: out std_ulogic;
    valid_i: in std_ulogic := '1';
    pixel_i: in nsl_video.pixel_stream.pixel_t;

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of pixel_stream_requester is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    -- Tell the generator a frame opens, then that a line does.  A
    -- stream has no blanking to state them in, so they take a cycle
    -- each of their own.
    ST_SOF,
    ST_SOL,
    ST_LINE
    );

  type regs_t is
  record
    state: state_t;
  end record;

  signal r, rin: regs_t;

  signal count_sof_s, count_eol_s, count_eof_s: std_ulogic;
  signal count_valid_s, count_ready_s: std_ulogic;
  signal count_keep_s: std_ulogic_vector(0 to config_c.pixel_count-1);
  signal pixels_s: nsl_video.pixel_stream.pixel_vector(0 to config_c.pixel_count-1);

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A generator answers one pixel at a time",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  counter: nsl_video.raster.raster_counter
    generic map(
      geometry_c => geometry_c,
      pixel_count_c => config_c.pixel_count
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      enable_i => enable_i,
      x_o => open,
      y_o => open,
      sof_o => count_sof_s,
      eol_o => count_eol_s,
      eof_o => count_eof_s,
      keep_o => count_keep_s,
      valid_o => count_valid_s,
      ready_i => count_ready_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, enable_i, valid_i, out_i,
                      count_valid_s, count_eol_s, count_eof_s) is
    variable taken: boolean;
  begin
    rin <= r;

    taken := r.state = ST_LINE
             and count_valid_s = '1'
             and valid_i = '1'
             and is_ready(config_c, out_i);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if enable_i = '1' then
          rin.state <= ST_SOF;
        end if;

      when ST_SOF =>
        rin.state <= ST_SOL;

      when ST_SOL =>
        rin.state <= ST_LINE;

      when ST_LINE =>
        if taken then
          if count_eof_s = '1' then
            if enable_i = '1' then
              rin.state <= ST_SOF;
            else
              rin.state <= ST_IDLE;
            end if;
          elsif count_eol_s = '1' then
            rin.state <= ST_SOL;
          end if;
        end if;
    end case;
  end process;

  pixels_s(0) <= pixel_i;

  mealy: process(r, count_valid_s, count_sof_s, count_eol_s, count_eof_s,
                 count_keep_s, valid_i, out_i, pixels_s) is
    variable offering: boolean;
  begin
    offering := r.state = ST_LINE
                and count_valid_s = '1'
                and valid_i = '1';

    out_o <= transfer(cfg => config_c,
                      pixels => pixels_s,
                      keep => count_keep_s,
                      valid => offering,
                      sof => count_sof_s = '1',
                      last => count_eol_s = '1',
                      eof => count_eof_s = '1');

    if offering and is_ready(config_c, out_i) then
      count_ready_s <= '1';
      ready_o <= '1';
    else
      count_ready_s <= '0';
      ready_o <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    sof_o <= '0';
    sol_o <= '0';

    case r.state is
      when ST_SOF =>
        sof_o <= '1';

      when ST_SOL =>
        sol_o <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
