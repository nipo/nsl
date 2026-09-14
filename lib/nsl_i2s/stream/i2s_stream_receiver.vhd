library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity i2s_stream_receiver is
  generic(
    config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    valid_i : in std_ulogic;
    channel_i : in std_ulogic;
    data_i : in unsigned(config_c.sample_bits-1 downto 0);

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t;

    overflow_o : out std_ulogic
    );
end entity;

architecture beh of i2s_stream_receiver is

  type regs_t is
  record
    -- A receiver holds valid up for a whole bit clock while the word
    -- it finished sits on its output, so what marks a word is the
    -- moment it went up rather than the time it stays there.
    valid: std_ulogic;

    -- The frame being put together, channel by channel
    gathering: frame_t;

    -- Frames already handed over in the packet being built
    count: natural range 0 to config_c.frames_per_packet-1;
    -- A frame went missing from this packet
    lost: std_ulogic;

    out_m: nsl_amba.axi4_stream.master_t;
    overflow: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "I2S carries two channels and no sideband",
      condition_c => config_c.channel_count = 2
      and config_c.sideband_bits = 0
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
      r.valid <= '0';
      r.gathering <= frame_zero_c;
      r.count <= 0;
      r.lost <= '0';
      r.out_m <= transfer_defaults(config_c);
      r.overflow <= '0';
    end if;
  end process;

  transition: process(r, valid_i, channel_i, data_i, out_i) is
    variable whole: frame_t;
    variable closing: boolean;
  begin
    rin <= r;
    rin.overflow <= '0';
    rin.valid <= valid_i;

    -- A beat taken makes room for the next
    if is_taken(config_c, r.out_m, out_i) then
      rin.out_m <= transfer_defaults(config_c);
    end if;

    if valid_i = '1' and r.valid = '0' then
      if channel_i = '0' then
        rin.gathering(0).sample <= to_sample(data_i, config_c.coding);
      else
        -- The frame is whole with this one
        whole := r.gathering;
        whole(1).sample := to_sample(data_i, config_c.coding);

        closing := r.count = config_c.frames_per_packet-1;

        if is_valid(config_c, r.out_m)
          and not is_taken(config_c, r.out_m, out_i) then
          -- Nowhere to put it.  The frame goes, and the packet it
          -- belonged to is no longer whole.
          rin.overflow <= '1';
          rin.lost <= '1';
        else
          rin.out_m <= transfer(
            cfg => config_c,
            frame => whole,
            last => closing,
            error => closing and r.lost = '1');

          if closing then
            rin.count <= 0;
            rin.lost <= '0';
          else
            rin.count <= r.count + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    out_o <= r.out_m;
    overflow_o <= r.overflow;
  end process;

end architecture;
