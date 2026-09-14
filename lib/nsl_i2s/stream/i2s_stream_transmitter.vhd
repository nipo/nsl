library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity i2s_stream_transmitter is
  generic(
    config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    ready_i : in std_ulogic;
    channel_i : in std_ulogic;
    data_o : out unsigned(config_c.sample_bits-1 downto 0);

    underflow_o : out std_ulogic
    );
end entity;

architecture beh of i2s_stream_transmitter is

  type regs_t is
  record
    held: frame_t;
    held_valid: std_ulogic;
    underflow: std_ulogic;
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
      r.held <= frame_zero_c;
      r.held_valid <= '0';
      r.underflow <= '0';
    end if;
  end process;

  transition: process(r, in_i, ready_i, channel_i) is
  begin
    rin <= r;
    rin.underflow <= '0';

    -- The last channel of the frame has gone, so the frame has
    if ready_i = '1' and channel_i = '1' then
      rin.held_valid <= '0';

      if r.held_valid = '0' then
        rin.underflow <= '1';
      end if;
    end if;

    if r.held_valid = '0' and is_valid(config_c, in_i) then
      rin.held <= frame(config_c, in_i);
      rin.held_valid <= '1';
    end if;
  end process;

  -- Taking a beat only while there is nowhere for it to go would stall
  -- the wire, so one is taken as soon as the last is spoken for.
  in_o <= accept(config_c, r.held_valid = '0');

  -- Which channel is wanted is known only as it is asked for
  mealy: process(r, channel_i) is
  begin
    if channel_i = '0' then
      data_o <= r.held(0).sample(config_c.sample_bits-1 downto 0);
    else
      data_o <= r.held(1).sample(config_c.sample_bits-1 downto 0);
    end if;
  end process;

  moore: process(r) is
  begin
    underflow_o <= r.underflow;
  end process;

end architecture;
