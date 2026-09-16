library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, work;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity pcm_peak_meter is
  generic(
    config_c : nsl_audio.pcm_stream.config_t;
    decay_l2_c : natural := 12
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    master_i : in nsl_amba.axi4_stream.master_t;
    slave_i : in nsl_amba.axi4_stream.slave_t;

    peak_o : out work.meter.peak_vector(0 to config_c.channel_count-1)
    );
end entity;

architecture beh of pcm_peak_meter is

  constant sample_bits_c: natural := config_c.sample_bits;
  constant channels_c: natural := config_c.channel_count;

  subtype level_t is unsigned(sample_bits_c-1 downto 0);
  type level_vector is array (natural range 0 to max_channel_count_c-1)
    of level_t;

  constant level_zero_c: level_t := (others => '0');
  -- Under this a halving rounds to nothing, so this is where the
  -- fall stops.
  constant floor_c: level_t := to_unsigned(2 ** decay_l2_c, sample_bits_c);

  type regs_t is
  record
    peak: level_vector;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.peak <= (others => level_zero_c);
    end if;
  end process;

  transition: process(r, master_i, slave_i) is
    variable taken: frame_t;
    variable sample: signed(sample_bits_c downto 0);
    variable magnitude, decayed: level_t;
  begin
    rin <= r;

    taken := frame(config_c, master_i);

    if is_taken(config_c, master_i, slave_i) then
      for c in 0 to channels_c-1
      loop
        sample := resize(signed(taken(c).sample(sample_bits_c-1 downto 0)),
                         sample_bits_c+1);

        if sample < 0 then
          magnitude := unsigned(resize(-sample, sample_bits_c));
        else
          magnitude := unsigned(resize(sample, sample_bits_c));
        end if;

        if r.peak(c) < floor_c then
          decayed := level_zero_c;
        else
          decayed := r.peak(c)
                     - resize(r.peak(c)(sample_bits_c-1 downto decay_l2_c),
                              sample_bits_c);
        end if;

        if magnitude > decayed then
          rin.peak(c) <= magnitude;
        else
          rin.peak(c) <= decayed;
        end if;
      end loop;
    end if;
  end process;

  moore: process(r) is
  begin
    for c in 0 to channels_c-1
    loop
      peak_o(c) <= resize(r.peak(c), peak_o(c)'length);
    end loop;
  end process;

end architecture;
