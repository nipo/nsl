library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis, work;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity spdif_stream_receiver is
  generic(
    config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    valid_i : in std_ulogic;
    block_start_i : in std_ulogic;
    channel_i : in std_ulogic;
    frame_i : in work.framer.frame_t;
    parity_ok_i : in std_ulogic := '1';

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t;

    overflow_o : out std_ulogic
    );
end entity;

architecture beh of spdif_stream_receiver is

  type regs_t is
  record
    -- The frame being put together, then the one held back so that the
    -- frame after it can say whether a block starts there
    gathering: frame_t;
    gathering_block: std_ulogic;

    held: frame_t;
    held_valid: std_ulogic;
    held_block: std_ulogic;

    count: natural range 0 to config_c.frames_per_packet-1;
    -- Something went wrong somewhere in the packet being built
    bad: std_ulogic;

    out_m: nsl_amba.axi4_stream.master_t;
    overflow: std_ulogic;
  end record;

  -- A subframe holds twenty bits of audio above four of auxiliary,
  -- which together are the twenty four bit sample a stream carries.
  function to_channel(f: work.framer.frame_t) return channel_t
  is
    variable ret: channel_t := channel_zero_c;
  begin
    ret.sample := to_sample(f.audio & f.aux, config_c.coding);
    ret.sideband(nsl_audio.metadata.sideband_v_c) := f.invalid;
    ret.sideband(nsl_audio.metadata.sideband_u_c) := f.user;
    ret.sideband(nsl_audio.metadata.sideband_c_c) := f.channel_status;
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
      r.gathering <= frame_zero_c;
      r.gathering_block <= '0';
      r.held_valid <= '0';
      r.held_block <= '0';
      r.count <= 0;
      r.bad <= '0';
      r.out_m <= transfer_defaults(config_c);
      r.overflow <= '0';
    end if;
  end process;

  transition: process(r, valid_i, block_start_i, channel_i, frame_i,
                      parity_ok_i, out_i) is
    variable whole: frame_t;
    variable closing: boolean;
  begin
    rin <= r;
    rin.overflow <= '0';

    -- A beat taken makes room for the next
    if is_taken(config_c, r.out_m, out_i) then
      rin.out_m <= transfer_defaults(config_c);
    end if;

    if valid_i = '1' then
      if channel_i = '0' then
        -- A block is said to start on the first subframe of a frame
        rin.gathering(0) <= to_channel(frame_i);
        rin.gathering_block <= block_start_i;
      else
        whole := r.gathering;
        whole(1) := to_channel(frame_i);

        -- The frame held back can go now: this one says whether a
        -- block opens where it would have ended.
        closing := r.gathering_block = '1'
                   or r.count = config_c.frames_per_packet-1;

        if r.held_valid = '1' then
          if is_valid(config_c, r.out_m)
            and not is_taken(config_c, r.out_m, out_i) then
            rin.overflow <= '1';
            rin.bad <= '1';
          else
            rin.out_m <= transfer(
              cfg => config_c,
              frame => r.held,
              last => closing,
              block_start => r.held_block = '1',
              error => closing and r.bad = '1');

            if closing then
              rin.count <= 0;
              rin.bad <= '0';
            else
              rin.count <= r.count + 1;
            end if;
          end if;
        end if;

        rin.held <= whole;
        rin.held_valid <= '1';
        rin.held_block <= r.gathering_block;
      end if;
    end if;

    -- Last, so that a subframe arriving broken marks the packet it is
    -- part of rather than the one just closed.  The frame being put
    -- together belongs to the packet after this one.
    if valid_i = '1' and parity_ok_i = '0' then
      rin.bad <= '1';
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= r.out_m;
    overflow_o <= r.overflow;
  end process;

end architecture;
