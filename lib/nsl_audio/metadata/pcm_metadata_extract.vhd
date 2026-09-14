library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_synthesis, work;
use work.pcm.all;
use work.pcm_stream.all;

entity pcm_metadata_extract is
  generic(
    in_config_c : work.pcm_stream.config_t;
    out_config_c : work.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t;

    block_valid_o : out std_ulogic;
    v_o, u_o, c_o : out work.pcm.block_bits_vector(0 to in_config_c.channel_count-1)
    );
end entity;

architecture beh of pcm_metadata_extract is

  constant channel_count_c : natural := in_config_c.channel_count;
  subtype acc_t is block_bits_vector(0 to channel_count_c-1);

  type regs_t is
  record
    -- Filling, a bit a beat
    v_acc, u_acc, c_acc: acc_t;
    -- How many beats of the block are in, so a packet of the wrong
    -- length can be told from one of the right one
    -- One past a block, so a packet longer than one can be told apart
    -- rather than wrapping round into looking right
    count: natural range 0 to block_frame_count_c;

    -- Whole, and left still while the next fills
    v, u, c: acc_t;
    valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Extracting takes a stream stating V, U and C and gives "
      & "one stating none, with the samples unchanged",
      condition_c => in_config_c.sideband_bits = 3
      and out_config_c.sideband_bits = 0
      and in_config_c.channel_count = out_config_c.channel_count
      and in_config_c.sample_bits = out_config_c.sample_bits
      and in_config_c.frames_per_packet = block_frame_count_c
      )
    port map(
      unused_i => '0'
      );

  -- Samples go straight on.  Only what rides beside them changes, so
  -- there is nothing to hold and nothing to wait for.
  out_o <= transfer(
    cfg => out_config_c,
    frame => frame(in_config_c, in_i),
    valid => is_valid(in_config_c, in_i),
    last => is_last(in_config_c, in_i),
    block_start => is_block(in_config_c, in_i),
    error => is_error(in_config_c, in_i));

  in_o <= out_i;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.count <= 0;
      r.valid <= '0';
      r.v <= (others => block_bits_zero_c);
      r.u <= (others => block_bits_zero_c);
      r.c <= (others => block_bits_zero_c);
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable f: frame_t;
    variable whole: boolean;
  begin
    rin <= r;
    rin.valid <= '0';

    if is_taken(in_config_c, in_i, out_i) then
      f := frame(in_config_c, in_i);

      -- Bits arrive oldest first, so shifting them in from the end
      -- leaves the first one where a reader looks for it
      for ch in 0 to channel_count_c-1
      loop
        rin.v_acc(ch) <= r.v_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_v_c);
        rin.u_acc(ch) <= r.u_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_u_c);
        rin.c_acc(ch) <= r.c_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_c_c);
      end loop;

      if is_last(in_config_c, in_i) then
        -- A packet of the right length holds a block; one of any other
        -- length holds bits that line up with nothing
        whole := r.count = block_frame_count_c-1;

        rin.count <= 0;

        if whole then
          for ch in 0 to channel_count_c-1
          loop
            rin.v(ch) <= r.v_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_v_c);
            rin.u(ch) <= r.u_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_u_c);
            rin.c(ch) <= r.c_acc(ch)(1 to block_frame_count_c-1)
                         & f(ch).sideband(work.metadata.sideband_c_c);
          end loop;
          rin.valid <= '1';
        end if;
      elsif r.count /= block_frame_count_c then
        rin.count <= r.count + 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    block_valid_o <= r.valid;
    v_o <= r.v;
    u_o <= r.u;
    c_o <= r.c;
  end process;

end architecture;
