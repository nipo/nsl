library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;
use nsl_video.pixel_stream.all;

entity pixel_stream_framer is
  generic(
    geometry_c: nsl_video.mode.geometry_t;
    config_c: nsl_video.pixel_stream.config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    enable_i: in std_ulogic := '1';

    x_o: out unsigned(nsl_video.mode.x_width(geometry_c)-1 downto 0);
    y_o: out unsigned(nsl_video.mode.y_width(geometry_c)-1 downto 0);
    pixel_i: in nsl_video.pixel_stream.pixel_vector(0 to config_c.pixel_count-1);
    taken_o: out std_ulogic;

    out_o: out nsl_video.pixel_stream.master_t;
    out_i: in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of pixel_stream_framer is

  signal sof_s, eol_s, eof_s, valid_s, ready_s: std_ulogic;
  signal keep_s: std_ulogic_vector(0 to config_c.pixel_count-1);

begin

  counter: nsl_video.raster.raster_counter
    generic map(
      geometry_c => geometry_c,
      pixel_count_c => config_c.pixel_count
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      enable_i => enable_i,
      x_o => x_o,
      y_o => y_o,
      sof_o => sof_s,
      eol_o => eol_s,
      eof_o => eof_s,
      keep_o => keep_s,
      valid_o => valid_s,
      ready_i => ready_s
      );

  ready_s <= '1' when is_ready(config_c, out_i) else '0';
  taken_o <= valid_s and ready_s;

  mealy: process(valid_s, sof_s, eol_s, eof_s, keep_s, pixel_i) is
  begin
    out_o <= transfer(cfg => config_c,
                      pixels => pixel_i,
                      keep => keep_s,
                      valid => valid_s = '1',
                      sof => sof_s = '1',
                      last => eol_s = '1',
                      eof => eof_s = '1');
  end process;

end architecture;
