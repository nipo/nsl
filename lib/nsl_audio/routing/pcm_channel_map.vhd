library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis, work;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity pcm_channel_map is
  generic(
    in_config_c : nsl_audio.pcm_stream.config_t;
    out_config_c : nsl_audio.pcm_stream.config_t;
    map_c : work.routing.channel_map_t
    );
  port(
    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of pcm_channel_map is

  alias map_a: work.routing.channel_map_t(0 to map_c'length-1) is map_c;

  function map_fits(m: work.routing.channel_map_t;
                    sources: natural) return boolean
  is
  begin
    for i in m'range
    loop
      if m(i) >= sources then
        return false;
      end if;
    end loop;
    return true;
  end function;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Channel map has one entry per output channel, "
      & "streams carry the same sample and sideband widths, "
      & "and every entry names a channel the input carries",
      condition_c => map_c'length = out_config_c.channel_count
      and in_config_c.sample_bits = out_config_c.sample_bits
      and in_config_c.sideband_bits = out_config_c.sideband_bits
      and in_config_c.coding = out_config_c.coding
      and map_fits(map_c, in_config_c.channel_count)
      )
    port map(
      unused_i => '0'
      );

  forward: process(in_i, out_i) is
    variable taken, put: frame_t;
  begin
    taken := frame(in_config_c, in_i);
    put := frame_zero_c;

    for c in 0 to out_config_c.channel_count-1
    loop
      put(c) := taken(map_a(c));
    end loop;

    out_o <= transfer(out_config_c, put,
                      valid => is_valid(in_config_c, in_i),
                      last => is_last(in_config_c, in_i),
                      block_start => is_block(in_config_c, in_i),
                      error => is_error(in_config_c, in_i));
  end process;

  in_o <= accept(in_config_c, is_ready(out_config_c, out_i));

end architecture;
