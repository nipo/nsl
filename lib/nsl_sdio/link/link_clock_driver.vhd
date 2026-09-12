library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity link_clock_driver is
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    half_cycle_m1_i: in unsigned;
    sample_phase_i: in unsigned;

    run_i: in std_ulogic;

    clk_o: out std_ulogic;

    drive_o: out std_ulogic;
    sample_o: out std_ulogic;

    running_o: out std_ulogic
    );
end entity;

architecture beh of link_clock_driver is

  type state_t is (
    ST_STOPPED,
    ST_RUN
    );

  type regs_t is
  record
    state: state_t;
    -- Value the clock output holds.  A rising edge reaches the pin
    -- one fabric cycle after the cycle that sets this.
    clk: std_ulogic;
    -- Fabric cycles left in the half period under way
    half: unsigned(half_cycle_m1_i'range);
    -- Fabric cycle of the period, zero being the one that starts with
    -- a rising edge on the pin
    phase: unsigned(half_cycle_m1_i'length downto 0);
    -- Whether the period under way still owes its sample.  A stop
    -- request lands before the sample of the period it ends, and
    -- what a card put on the wires for that period stays there for as
    -- long as the clock is away, so the debt is settled on the way
    -- back rather than written off.
    sample_pending: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_STOPPED;
      r.clk <= '0';
      r.sample_pending <= '0';
    end if;
  end process;

  transition: process(r, half_cycle_m1_i, sample_phase_i, run_i) is
  begin
    rin <= r;

    case r.state is
      when ST_STOPPED =>
        -- Resuming starts with a whole low half period, so a clock
        -- that stopped mid period does not come back with a runt one,
        -- and with whatever sample the stop left owed.
        if run_i = '1' then
          rin.state <= ST_RUN;
          rin.clk <= '0';
          rin.half <= half_cycle_m1_i;
          rin.sample_pending <= '0';
        end if;

      when ST_RUN =>
        if r.sample_pending = '1' and r.phase = sample_phase_i then
          rin.sample_pending <= '0';
        end if;

        if r.half /= 0 then
          rin.half <= r.half - 1;
          rin.phase <= r.phase + 1;
        elsif r.clk = '0' then
          -- Launching a rising edge, which opens a period
          rin.clk <= '1';
          rin.half <= half_cycle_m1_i;
          rin.phase <= (others => '0');
          rin.sample_pending <= '1';
        elsif run_i = '1' then
          rin.clk <= '0';
          rin.half <= half_cycle_m1_i;
          rin.phase <= r.phase + 1;
        else
          -- Stopping here leaves the low half unfinished, which the
          -- resume above makes up for.  Any later would mean a rising
          -- edge owed to whatever drive_o has just put on the wires,
          -- and a card reading the same bit twice.
          rin.state <= ST_STOPPED;
          rin.clk <= '0';
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    clk_o <= r.clk;

    case r.state is
      when ST_STOPPED =>
        running_o <= '0';

      when ST_RUN =>
        running_o <= '1';
    end case;
  end process;

  mealy: process(r, sample_phase_i, run_i) is
  begin
    drive_o <= '0';
    sample_o <= '0';

    case r.state is
      when ST_RUN =>
        -- Launching a falling edge, half a period ahead of the rising
        -- edge that carries what is put on the wires here.  A stop
        -- request takes this cycle instead, as the clock would not
        -- come back in time to carry the value out.
        if r.half = 0 and r.clk = '1' and run_i = '1' then
          drive_o <= '1';
        end if;

        if r.sample_pending = '1' and r.phase = sample_phase_i then
          sample_o <= '1';
        end if;

      when ST_STOPPED =>
        -- The way back settles what the stop took away.  The value
        -- that did not make it to the wires goes there now, a whole
        -- low half ahead of the edge that will carry it, as a card
        -- reading the same bit twice is what stopping any later
        -- would have cost.  The sample that was not taken is taken
        -- too: the wires still hold what the card put there for the
        -- edge it answered.
        if run_i = '1' then
          drive_o <= '1';

          if r.sample_pending = '1' then
            sample_o <= '1';
          end if;
        end if;
    end case;
  end process;

end architecture;
