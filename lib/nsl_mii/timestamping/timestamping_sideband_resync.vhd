library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_clocking;
use work.timestamping.all;

entity timestamping_sideband_resync is
  port(
    reset_n_i : in std_ulogic;

    a_clock_i : in std_ulogic;
    a_strobe_i : in std_ulogic;
    a_id_i : in tag_id_t;
    a_done_o : out std_ulogic;

    b_clock_i : in std_ulogic;
    b_strobe_o : out std_ulogic;
    b_id_o : out tag_id_t
    );
end entity;

architecture beh of timestamping_sideband_resync is

  signal clock_s: std_ulogic_vector(0 to 1);
  signal reset_n_s: std_ulogic_vector(0 to 1);

  signal a_data_s, b_data_s: std_ulogic_vector(tag_id_t'length-1 downto 0);
  signal a_valid_s, a_ready_s, b_valid_s, b_ready_s: std_ulogic;

begin

  clock_s(0) <= a_clock_i;
  clock_s(1) <= b_clock_i;

  reset_sync: nsl_clocking.async.async_multi_reset
    generic map(
      domain_count_c => 2
      )
    port map(
      clock_i => clock_s,
      master_i => reset_n_i,
      slave_o => reset_n_s
      );

  -- The identifier crosses as a one-word transfer.  What matters as
  -- much as the word itself is the handshake the slice runs
  -- underneath: the input side only becomes ready again once the
  -- output side acknowledged, resynchronized back to the a domain.
  crossing: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => tag_id_t'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_s,

      in_data_i => a_data_s,
      in_valid_i => a_valid_s,
      in_ready_o => a_ready_s,

      out_data_o => b_data_s,
      out_valid_o => b_valid_s,
      out_ready_i => b_ready_s
      );

  a_side: block is
    type state_t is (
      -- No event in flight.
      ST_IDLE,
      -- Offering the event to the crossing.
      ST_PUSH,
      -- Crossing took the event, waiting for the far side to consume
      -- it.
      ST_WAIT
      );

    type regs_t is
    record
      state: state_t;
      id: tag_id_t;
      done: std_ulogic;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(a_clock_i, reset_n_s(0)) is
    begin
      if rising_edge(a_clock_i) then
        r <= rin;
      end if;

      if reset_n_s(0) = '0' then
        r.state <= ST_IDLE;
        r.done <= '0';
      end if;
    end process;

    transition: process(r, a_strobe_i, a_id_i, a_ready_s) is
    begin
      rin <= r;
      rin.done <= '0';

      case r.state is
        when ST_IDLE =>
          if a_strobe_i = '1' then
            rin.state <= ST_PUSH;
            rin.id <= a_id_i;
          end if;

        when ST_PUSH =>
          if a_ready_s = '1' then
            rin.state <= ST_WAIT;
          end if;

        when ST_WAIT =>
          -- Readiness only comes back after the b side accepted the
          -- word and its acknowledge crossed back.  The b side
          -- accepts on the very edge it hands the strobe to its
          -- consumer, so by the time this is seen here, the
          -- consumer's register already holds the event.  That is
          -- what makes done_o safe to read a b-domain register on.
          if a_ready_s = '1' then
            rin.state <= ST_IDLE;
            rin.done <= '1';
          end if;
      end case;
    end process;

    moore: process(r) is
    begin
      a_data_s <= std_ulogic_vector(r.id);
      a_done_o <= r.done;

      if r.state = ST_PUSH then
        a_valid_s <= '1';
      else
        a_valid_s <= '0';
      end if;
    end process;

    check: process(a_clock_i) is
    begin
      if rising_edge(a_clock_i) and reset_n_s(0) = '1' then
        assert a_strobe_i = '0' or r.state = ST_IDLE
          report "Strobe while the previous event is still in flight"
          severity failure;
      end if;
    end process;
  end block;

  b_side: block is
    type regs_t is
    record
      strobe: std_ulogic;
      id: tag_id_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(b_clock_i, reset_n_s(1)) is
    begin
      if rising_edge(b_clock_i) then
        r <= rin;
      end if;

      if reset_n_s(1) = '0' then
        r.strobe <= '0';
      end if;
    end process;

    -- Acknowledging the crossing on the cycle the strobe is presented
    -- rather than on the cycle the word appears keeps the
    -- acknowledge, and therefore done_o, behind the consumer's
    -- capture edge.
    transition: process(r, b_valid_s, b_data_s) is
    begin
      rin <= r;
      rin.strobe <= '0';

      if r.strobe = '0' and b_valid_s = '1' then
        rin.strobe <= '1';
        rin.id <= unsigned(b_data_s);
      end if;
    end process;

    moore: process(r) is
    begin
      b_strobe_o <= r.strobe;
      b_id_o <= r.id;
      b_ready_s <= r.strobe;
    end process;
  end block;

end architecture;
