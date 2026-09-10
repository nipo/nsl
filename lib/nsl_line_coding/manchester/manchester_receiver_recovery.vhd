library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity manchester_receiver_recovery is
  generic (
    clock_i_hz_c : natural;
    signal_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in std_ulogic;

    bit_o : out std_ulogic;
    valid_o : out std_ulogic;

    active_o : out std_ulogic
    );
end entity;

architecture beh of manchester_receiver_recovery is

  constant bit_c : natural := clock_i_hz_c / signal_hz_c;

  -- Intervals between line transitions may only be a half bit time
  -- (cell boundary to mid-bit, or mid-bit to cell boundary) or a full
  -- bit time (mid-bit to mid-bit).  Decision thresholds sit halfway
  -- between the expected values, this gives each class the widest
  -- tolerance an interval measurement can offer.
  constant short_c : natural := bit_c / 4;
  constant full_c : natural := (bit_c * 3) / 4;
  constant idle_c : natural := (bit_c * 3) / 2;

  type state_t is (
    -- Line is quiet, next transition is taken as a mid-bit
    -- transition.
    ST_IDLE,
    -- Last transition was a mid-bit (data) transition.
    ST_MID,
    -- Last transition was a cell boundary transition, next one is
    -- necessarily a mid-bit transition.
    ST_BOUNDARY
    );

  type regs_t is
  record
    state: state_t;
    data: std_ulogic;
    -- Clock cycles elapsed since last accepted transition, saturating.
    counter: natural range 0 to idle_c;
    value: std_ulogic;
    valid: std_ulogic;
    active: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  assert clock_i_hz_c mod (2 * signal_hz_c) = 0
    report "clock_i_hz_c must be an integer multiple of 2 * signal_hz_c"
    severity failure;

  assert bit_c >= 8
    report "clock_i_hz_c must be at least 8 * signal_hz_c"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.data <= '0';
      r.counter <= 0;
      r.value <= '0';
      r.valid <= '0';
      r.active <= '0';
    end if;
  end process;

  transition: process(r, data_i) is
    variable edge_v, data_edge_v : boolean;
  begin
    rin <= r;
    rin.valid <= '0';
    rin.data <= data_i;

    -- While idle, transitions are only taken into account once line
    -- has been seen quiet for a full idle timeout.  This avoids
    -- reacting on the level the line happens to have on reset
    -- deassertion.
    edge_v := (data_i /= r.data)
              and not ((r.state = ST_IDLE) and (r.counter < idle_c));

    -- A full bit time interval always ends on a mid-bit transition,
    -- and so does any transition following a cell boundary one.  An
    -- interval matching neither expectation makes us relock on the
    -- spot, taking this transition as a mid-bit one.
    data_edge_v := (r.state /= ST_MID)
                   or (r.counter >= full_c)
                   or (r.counter < short_c);

    if edge_v then
      rin.counter <= 1;

      if data_edge_v then
        rin.state <= ST_MID;
        rin.value <= data_i;
        rin.valid <= '1';
        rin.active <= '1';
      else
        rin.state <= ST_BOUNDARY;
      end if;
    elsif r.counter < idle_c then
      rin.counter <= r.counter + 1;
    elsif r.state /= ST_IDLE then
      rin.state <= ST_IDLE;
      rin.active <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    bit_o <= r.value;
    valid_o <= r.valid;
    active_o <= r.active;
  end process;

end architecture;
