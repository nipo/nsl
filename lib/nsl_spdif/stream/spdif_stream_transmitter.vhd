library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis, work;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity spdif_stream_transmitter is
  generic(
    config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    ready_i : in std_ulogic;
    block_start_o : out std_ulogic;
    channel_o : out std_ulogic;
    frame_o : out work.framer.frame_t;

    underflow_o : out std_ulogic
    );
end entity;

architecture beh of spdif_stream_transmitter is

  type regs_t is
  record
    held: frame_t;
    held_valid: std_ulogic;
    held_block: std_ulogic;

    -- Which subframe of the frame goes next
    channel: std_ulogic;
    underflow: std_ulogic;
  end record;

  function to_subframe(c: channel_t) return work.framer.frame_t
  is
    variable ret: work.framer.frame_t;
  begin
    ret.aux := c.sample(3 downto 0);
    ret.audio := c.sample(23 downto 4);
    ret.invalid := c.sideband(nsl_audio.metadata.sideband_v_c);
    ret.user := c.sideband(nsl_audio.metadata.sideband_u_c);
    ret.channel_status := c.sideband(nsl_audio.metadata.sideband_c_c);
    return ret;
  end function;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An IEC 60958 link carries two channels of twenty four "
      & "bits with three bits beside each, in packets of a block",
      condition_c => config_c.channel_count = 2
      and config_c.sample_bits = 24
      and config_c.sideband_bits = 3
      and config_c.frames_per_packet = block_frame_count_c
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
      r.held <= frame_zero_c;
      r.held_valid <= '0';
      r.held_block <= '0';
      r.channel <= '0';
      r.underflow <= '0';
    end if;
  end process;

  transition: process(r, in_i, ready_i) is
  begin
    rin <= r;
    rin.underflow <= '0';

    if ready_i = '1' then
      rin.channel <= not r.channel;

      -- Both subframes have gone, so the frame has
      if r.channel = '1' then
        rin.held_valid <= '0';

        if r.held_valid = '0' then
          rin.underflow <= '1';
        end if;
      end if;
    end if;

    if r.held_valid = '0' and is_valid(config_c, in_i) then
      rin.held <= frame(config_c, in_i);
      rin.held_block <= '0';
      if is_block(config_c, in_i) then
        rin.held_block <= '1';
      end if;
      rin.held_valid <= '1';
    end if;
  end process;

  in_o <= accept(config_c, r.held_valid = '0');

  moore: process(r) is
  begin
    channel_o <= r.channel;
    -- A block is stated on the first subframe of the first frame of one
    block_start_o <= r.held_block and not r.channel;
    frame_o <= to_subframe(r.held(0));

    if r.channel = '1' then
      frame_o <= to_subframe(r.held(1));
    end if;

    underflow_o <= r.underflow;
  end process;

end architecture;
