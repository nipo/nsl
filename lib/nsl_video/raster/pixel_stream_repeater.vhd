library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity pixel_stream_repeater is
  generic(
    config_c: nsl_video.pixel_stream.config_t;
    factor_c: positive
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    in_i: in nsl_video.pixel_stream.master_t;
    in_o: out nsl_video.pixel_stream.slave_t;

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of pixel_stream_repeater is

  type regs_t is
  record
    -- A beat is held, and how many copies of it are still to go
    -- after the one on offer.
    full: boolean;
    left: natural range 0 to factor_c-1;
    first: boolean;
    pixel: pixel_t;
    sof, last, eof, error: boolean;
  end record;

  signal r, rin: regs_t;

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Repeater copies whole beats, stream must hold one pixel per beat",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.full <= false;
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable free: boolean;
  begin
    rin <= r;

    free := not r.full;

    if r.full and is_ready(config_c, out_i) then
      if r.left = 0 then
        free := true;
        rin.full <= false;
      else
        rin.left <= r.left - 1;
        rin.first <= false;
      end if;
    end if;

    if free and is_valid(config_c, in_i) then
      rin.full <= true;
      rin.left <= factor_c-1;
      rin.first <= true;
      rin.pixel <= pixel(config_c, in_i);
      rin.sof <= is_sof(config_c, in_i);
      rin.last <= is_last(config_c, in_i);
      rin.eof <= is_eof(config_c, in_i);
      rin.error <= is_error(config_c, in_i);
    end if;
  end process;

  mealy: process(r, out_i) is
  begin
    in_o <= accept(config_c,
                   ready => not r.full
                   or (r.left = 0 and is_ready(config_c, out_i)));
  end process;

  moore: process(r) is
    variable closing: boolean;
  begin
    closing := r.left = 0;

    out_o <= transfer(config_c, r.pixel,
                      valid => r.full,
                      sof => r.first and r.sof,
                      last => closing and r.last,
                      eof => closing and r.eof,
                      error => closing and r.error);
  end process;

end architecture;
