library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis, work;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity hdmi_audio_stream_source is
  generic(
    config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    valid_i : in std_ulogic;
    a_i, b_i : in work.audio.channel_sample_t;
    block_start_i : in std_ulogic;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t;

    overflow_o : out std_ulogic
    );
end entity;

architecture beh of hdmi_audio_stream_source is

  -- IEC 60958 states three bits alongside a sample, in this order
  constant sideband_v_c : natural := 0;
  constant sideband_u_c : natural := 1;
  constant sideband_c_c : natural := 2;

  type regs_t is
  record
    -- The frame held back one place, so that the frame after it can
    -- say whether a block starts there
    held: frame_t;
    held_valid: std_ulogic;
    held_block: std_ulogic;

    -- Frames already handed over in the packet being built
    count: natural range 0 to config_c.frames_per_packet-1;
    -- A frame went missing from this packet
    lost: std_ulogic;

    out_m: nsl_amba.axi4_stream.master_t;
    overflow: std_ulogic;
  end record;

  function to_frame(a, b: work.audio.channel_sample_t) return frame_t
  is
    variable ret: frame_t := frame_zero_c;
  begin
    ret(0).sample := to_sample(a.data, config_c.coding);
    ret(0).sideband(sideband_v_c) := a.v;
    ret(0).sideband(sideband_u_c) := a.u;
    ret(0).sideband(sideband_c_c) := a.c;

    ret(1).sample := to_sample(b.data, config_c.coding);
    ret(1).sideband(sideband_v_c) := b.v;
    ret(1).sideband(sideband_u_c) := b.u;
    ret(1).sideband(sideband_c_c) := b.c;

    return ret;
  end function;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An HDMI link carries two channels of twenty four bits, "
      & "so a stream taking them states as much",
      condition_c => config_c.channel_count = 2
      and config_c.sample_bits = 24
      and (config_c.sideband_bits = 0 or config_c.sideband_bits = 3)
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
      r.held_valid <= '0';
      r.held_block <= '0';
      r.count <= 0;
      r.lost <= '0';
      r.out_m <= transfer_defaults(config_c);
      r.overflow <= '0';
    end if;
  end process;

  transition: process(r, valid_i, a_i, b_i, block_start_i, out_i) is
    variable closing, short, blocked: boolean;
  begin
    rin <= r;
    rin.overflow <= '0';

    -- A beat taken makes room for the next
    if is_taken(config_c, r.out_m, out_i) then
      rin.out_m <= transfer_defaults(config_c);
    end if;

    if valid_i = '1' then
      -- The frame held back can go now: the one arriving says whether
      -- a block opens where it would have ended.
      blocked := block_start_i = '1';
      closing := blocked or r.count = config_c.frames_per_packet-1;
      short := blocked and r.count /= config_c.frames_per_packet-1;

      if r.held_valid = '1' then
        if is_valid(config_c, r.out_m)
          and not is_taken(config_c, r.out_m, out_i) then
          -- Nowhere to put it.  The frame goes, and the packet it
          -- belonged to is no longer whole.
          rin.overflow <= '1';
          rin.lost <= '1';
        else
          rin.out_m <= transfer(
            cfg => config_c,
            frame => r.held,
            last => closing,
            block_start => r.held_block = '1',
            error => closing and (short or r.lost = '1'));

          if closing then
            rin.count <= 0;
            rin.lost <= '0';
          else
            rin.count <= r.count + 1;
          end if;
        end if;
      end if;

      rin.held <= to_frame(a_i, b_i);
      rin.held_valid <= '1';
      rin.held_block <= block_start_i;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= r.out_m;
    overflow_o <= r.overflow;
  end process;

end architecture;
