library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, work;
use work.timestamp.all;

entity discipline_step_applier is
  port(
    reset_n_i : in std_ulogic;

    clock_i : in std_ulogic;
    reference_i : in timestamp_t;
    sync_i : in timestamp_t;
    valid_i : in std_ulogic;

    rtc_clock_i : in std_ulogic;
    timestamp_i : in timestamp_t;
    timestamp_o : out timestamp_t;
    timestamp_set_o : out std_ulogic
    );
end entity;

architecture beh of discipline_step_applier is

  constant ns_per_second_c : natural := 1000000000;

  -- Second arithmetic domain: a full-range second field either sign,
  -- plus a second field of the time base, plus the normalization
  -- carries.
  subtype sec_t is signed(35 downto 0);
  -- Nanosecond arithmetic domain: a nanosecond field plus or minus a
  -- whole second.
  subtype ns_t is signed(33 downto 0);

  constant ns_c : ns_t := to_signed(ns_per_second_c, ns_t'length);

  constant ts_width_c : natural
    := timestamp_second_t'length + timestamp_nanosecond_t'length;

  function ts_pack(ts : timestamp_t) return std_ulogic_vector
  is
  begin
    return std_ulogic_vector(ts.second) & std_ulogic_vector(ts.nanosecond);
  end function;

  function ts_unpack(v : std_ulogic_vector) return timestamp_t
  is
    alias xv : std_ulogic_vector(ts_width_c-1 downto 0) is v;
    variable ret : timestamp_t;
  begin
    ret.abs_change := '0';
    ret.second := unsigned(xv(ts_width_c-1
                              downto timestamp_nanosecond_t'length));
    ret.nanosecond := unsigned(xv(timestamp_nanosecond_t'length-1 downto 0));
    return ret;
  end function;

  -- abs_change is not carried: the output asserts it unconditionally,
  -- a step is an absolute change by definition.
  signal cross_data_s, crossed_data_s
    : std_ulogic_vector(2*ts_width_c-1 downto 0);
  signal crossed_valid_s, crossed_ready_s : std_ulogic;

begin

  cross_data_s <= ts_pack(reference_i) & ts_pack(sync_i);

  -- A command arriving while the slice still holds the previous one is
  -- dropped: in_ready_o is left unconnected and in_valid_i is a plain
  -- strobe.  Steps are rare, and a dropped one is re-issued by the
  -- protocol engine on its next measurement.
  crossing: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => 2*ts_width_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,
      clock_i(1) => rtc_clock_i,

      in_data_i => cross_data_s,
      in_valid_i => valid_i,
      in_ready_o => open,

      out_data_o => crossed_data_s,
      out_ready_i => crossed_ready_s,
      out_valid_o => crossed_valid_s
      );

  rtc_side: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      -- reference - sync, then its normalization
      ST_DIFF,
      ST_DIFF_NORM,
      -- timestamp_i + the above, then its normalization
      ST_ADD,
      ST_ADD_NORM,
      ST_SET
      );

    type regs_t is
    record
      state : state_t;
      reference : timestamp_t;
      sync : timestamp_t;
      ds : sec_t;
      dn : ns_t;
      res_s : sec_t;
      res_n : ns_t;
    end record;

    signal r, rin : regs_t;
  begin
    regs: process(rtc_clock_i, reset_n_i) is
    begin
      if rising_edge(rtc_clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, crossed_data_s, crossed_valid_s, timestamp_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if crossed_valid_s = '1' then
            rin.reference <= ts_unpack(crossed_data_s(2*ts_width_c-1
                                                      downto ts_width_c));
            rin.sync <= ts_unpack(crossed_data_s(ts_width_c-1 downto 0));
            rin.state <= ST_DIFF;
          end if;

        when ST_DIFF =>
          -- The two timestamps are arbitrarily far apart: the second
          -- parts subtract at full width, they are not an offset that
          -- has to fit a nanosecond range.
          rin.ds <= signed(resize(r.reference.second, sec_t'length))
                    - signed(resize(r.sync.second, sec_t'length));
          rin.dn <= signed(resize(r.reference.nanosecond, ns_t'length))
                    - signed(resize(r.sync.nanosecond, ns_t'length));
          rin.state <= ST_DIFF_NORM;

        when ST_DIFF_NORM =>
          if r.dn < 0 then
            rin.dn <= r.dn + ns_c;
            rin.ds <= r.ds - 1;
          end if;
          rin.state <= ST_ADD;

        when ST_ADD =>
          -- The time base keeps running while this sequence executes,
          -- so the local time is read here, as late as the arithmetic
          -- allows.  The step still lands three rtc_clock_i cycles
          -- after this read: one to normalize, one to hold
          -- timestamp_set_o, one for the time base to take it.  That
          -- residual is a constant lag of three periods of the time
          -- base clock, 30 ns at 100 MHz, and it does not accumulate.
          -- Folding it in would take the per-cycle increment, which is
          -- not part of this interface.
          rin.res_n <= r.dn
                       + signed(resize(timestamp_i.nanosecond, ns_t'length));
          rin.res_s <= r.ds
                       + signed(resize(timestamp_i.second, sec_t'length));
          rin.state <= ST_ADD_NORM;

        when ST_ADD_NORM =>
          -- Both terms were normalized, so the sum is short of two
          -- seconds and one carry is enough.
          if r.res_n >= ns_c then
            rin.res_n <= r.res_n - ns_c;
            rin.res_s <= r.res_s + 1;
          end if;
          rin.state <= ST_SET;

        when ST_SET =>
          rin.state <= ST_IDLE;
      end case;
    end process;

    moore: process(r) is
    begin
      timestamp_o.abs_change <= '1';
      timestamp_o.second <= unsigned(r.res_s(timestamp_second_t'length-1
                                             downto 0));
      timestamp_o.nanosecond
        <= unsigned(r.res_n(timestamp_nanosecond_t'length-1 downto 0));

      if r.state = ST_SET then
        timestamp_set_o <= '1';
      else
        timestamp_set_o <= '0';
      end if;

      if r.state = ST_IDLE then
        crossed_ready_s <= '1';
      else
        crossed_ready_s <= '0';
      end if;
    end process;
  end block;

end architecture;
