library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, work;
use work.timestamp.all;
use work.discipline.all;

entity discipline_pps_source is
  generic(
    align_threshold_ns_c : natural := 10000;
    -- Latency from the pulse edge on the pin to its detection here,
    -- taken off the sampled time: the input resynchronizer alone is
    -- five cycles of clock_i.
    input_delay_ns_c : natural := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    pps_i : in std_ulogic;

    timestamp_i : in timestamp_t;

    offset_o : out timestamp_nanosecond_offset_t;
    offset_valid_o : out std_ulogic;

    adj_o : out timestamp_nanosecond_offset_t;
    adj_valid_o : out std_ulogic;

    tick_o : out std_ulogic
    );
end entity;

architecture beh of discipline_pps_source is

  subtype offset_t is timestamp_nanosecond_offset_t;

  constant second_ns_c : offset_t := to_signed(1000000000, offset_t'length);
  constant half_second_ns_c : offset_t := to_signed(500000000, offset_t'length);
  constant threshold_c : offset_t := to_signed(align_threshold_ns_c,
                                               offset_t'length);

  type regs_t is
  record
    -- Nanosecond field as read on the cycle the resynchronized pulse
    -- was seen, and the same instant counted from the next second
    -- boundary instead of the past one.
    sampled : offset_t;
    sampled_valid : std_ulogic;
    folded : offset_t;
    behind : std_ulogic;
    folded_valid : std_ulogic;

    offset : offset_t;
    offset_valid : std_ulogic;
    adj : offset_t;
    adj_valid : std_ulogic;

    tick : std_ulogic;
  end record;

  signal r, rin : regs_t;
  signal pps_rising_s : std_ulogic;

begin

  assert align_threshold_ns_c < 500000000
    report "Alignment threshold must stay below half a second"
    severity failure;

  input: nsl_clocking.async.async_input
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => pps_i,
      data_o => open,
      rising_o => pps_rising_s,
      falling_o => open
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.sampled_valid <= '0';
      r.folded_valid <= '0';
      r.behind <= '0';
      r.offset_valid <= '0';
      r.adj_valid <= '0';
      r.tick <= '0';
    end if;
  end process;

  -- Every pulse is taken at face value: an engine that dropped a
  -- second pulse arriving too soon after the previous one would also
  -- drop the first valid pulse after a receiver relocks its fix, so
  -- qualifying the pulse train is left to whoever drives enable_i.
  transition: process(r, pps_rising_s, timestamp_i, enable_i) is
    variable offset_v : offset_t;
    variable aligned_v : boolean;
  begin
    rin <= r;

    rin.sampled_valid <= '0';
    rin.folded_valid <= '0';
    rin.offset_valid <= '0';
    rin.adj_valid <= '0';
    rin.tick <= '0';

    if pps_rising_s = '1' then
      rin.sampled <= signed(resize(timestamp_i.nanosecond, offset_t'length))
                     - to_signed(input_delay_ns_c, offset_t'length);
      rin.sampled_valid <= '1';
      rin.tick <= '1';
    end if;

    if r.sampled_valid = '1' then
      rin.folded <= r.sampled - second_ns_c;
      if r.sampled >= half_second_ns_c then
        rin.behind <= '1';
      else
        rin.behind <= '0';
      end if;
      rin.folded_valid <= '1';
    end if;

    if r.behind = '1' then
      offset_v := r.folded;
    else
      offset_v := r.sampled;
    end if;
    aligned_v := offset_v <= threshold_c and offset_v >= -threshold_c;

    if r.folded_valid = '1' then
      if aligned_v then
        rin.offset <= offset_v;
        rin.offset_valid <= '1';
      else
        rin.adj <= -offset_v;
        rin.adj_valid <= '1';
      end if;
    end if;

    if enable_i = '0' then
      rin.sampled_valid <= '0';
      rin.folded_valid <= '0';
      rin.offset_valid <= '0';
      rin.adj_valid <= '0';
      rin.tick <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    offset_o <= r.offset;
    offset_valid_o <= r.offset_valid;
    adj_o <= r.adj;
    adj_valid_o <= r.adj_valid;
    tick_o <= r.tick;
  end process;

end architecture;
