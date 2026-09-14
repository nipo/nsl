library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_synthesis, work;
use work.pcm.all;
use work.pcm_stream.all;

entity pcm_metadata_merge is
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

    block_valid_i : in std_ulogic := '0';
    block_ready_o : out std_ulogic;
    v_i, u_i, c_i : in work.pcm.block_bits_vector(0 to out_config_c.channel_count-1)
    );
end entity;

architecture beh of pcm_metadata_merge is

  constant channel_count_c : natural := out_config_c.channel_count;
  subtype acc_t is block_bits_vector(0 to channel_count_c-1);

  type regs_t is
  record
    -- Turned round rather than shifted out, so a block held for want
    -- of a new one comes back to its own beginning and is sent again
    v, u, c: acc_t;
    count: natural range 0 to block_frame_count_c-1;
  end record;

  signal r, rin: regs_t;

  signal taken_s: boolean;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Merging takes a stream stating no sideband and gives one "
      & "stating V, U and C, with the samples unchanged",
      condition_c => in_config_c.sideband_bits = 0
      and out_config_c.sideband_bits = 3
      and in_config_c.channel_count = out_config_c.channel_count
      and in_config_c.sample_bits = out_config_c.sample_bits
      and out_config_c.frames_per_packet = block_frame_count_c
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
      r.count <= 0;
      r.v <= (others => block_bits_zero_c);
      r.u <= (others => block_bits_zero_c);
      r.c <= (others => block_bits_zero_c);
    end if;
  end process;

  -- Samples go straight on, as in the other direction.  What the
  -- packets are cut to is this block's doing, though: whatever the
  -- stream arriving was cut to, the bits going out need blocks.
  mealy: process(r, in_i, out_i) is
    variable f: frame_t;
  begin
    f := frame(in_config_c, in_i);

    for ch in 0 to channel_count_c-1
    loop
      f(ch).sideband(work.metadata.sideband_v_c) := r.v(ch)(0);
      f(ch).sideband(work.metadata.sideband_u_c) := r.u(ch)(0);
      f(ch).sideband(work.metadata.sideband_c_c) := r.c(ch)(0);
    end loop;

    out_o <= transfer(
      cfg => out_config_c,
      frame => f,
      valid => is_valid(in_config_c, in_i),
      last => r.count = block_frame_count_c-1,
      block_start => r.count = 0);
  end process;

  in_o <= out_i;

  taken_s <= is_valid(in_config_c, in_i) and is_ready(out_config_c, out_i);

  -- A block is taken as the one before it ends, so nothing is ever
  -- half one and half another
  block_ready_o <= '1' when taken_s and r.count = block_frame_count_c-1
                   else '0';

  transition: process(r, taken_s, block_valid_i, v_i, u_i, c_i) is
  begin
    rin <= r;

    if taken_s then
      if r.count = block_frame_count_c-1 then
        rin.count <= 0;

        if block_valid_i = '1' then
          rin.v <= v_i;
          rin.u <= u_i;
          rin.c <= c_i;
        else
          -- Nothing new, so the one in hand comes round again
          for ch in 0 to channel_count_c-1
          loop
            rin.v(ch) <= r.v(ch)(1 to block_frame_count_c-1) & r.v(ch)(0);
            rin.u(ch) <= r.u(ch)(1 to block_frame_count_c-1) & r.u(ch)(0);
            rin.c(ch) <= r.c(ch)(1 to block_frame_count_c-1) & r.c(ch)(0);
          end loop;
        end if;
      else
        rin.count <= r.count + 1;

        for ch in 0 to channel_count_c-1
        loop
          rin.v(ch) <= r.v(ch)(1 to block_frame_count_c-1) & r.v(ch)(0);
          rin.u(ch) <= r.u(ch)(1 to block_frame_count_c-1) & r.u(ch)(0);
          rin.c(ch) <= r.c(ch)(1 to block_frame_count_c-1) & r.c(ch)(0);
        end loop;
      end if;
    end if;
  end process;

end architecture;
