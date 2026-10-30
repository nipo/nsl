library ieee;
use ieee.std_logic_1164.all;

-- Reset sequencer for the CPLL of a GTHE4 channel.
--
-- Holds the CPLL powered down for hold_delay_c cycles, waits for the
-- transceiver power to be good, then powers the CPLL up and reports done.
--
-- power_good_i must already be synchronous to clock_i.
entity gthe4_cpll_reset_fsm is
  generic(
    -- 2us (plus margin) in clock_i cycles
    hold_delay_c : natural
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    power_good_i : in std_ulogic;

    pll_pd_o : out std_ulogic;
    done_o   : out std_ulogic
    );
end entity;

architecture beh of gthe4_cpll_reset_fsm is

  type reset_state_pll_t is (
    ST_RESET,
    ST_HOLD_RST,
    ST_WAIT_PWR_GOOD,
    ST_DONE);

  type regs_pll_t is
  record
    state     : reset_state_pll_t;
    pll_count : natural;
    pll_pd    : std_ulogic;
    pll_done  : std_ulogic;
  end record;

  signal r_pll, rin_pll : regs_pll_t;

begin

  pll_pd_o <= r_pll.pll_pd;
  done_o   <= r_pll.pll_done;

  reg_pll : process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r_pll <= rin_pll;
    end if;

    if reset_n_i = '0' then
      r_pll.state <= ST_RESET;
    end if;
  end process;

  transition_pll : process(r_pll, power_good_i) is

  begin
    rin_pll <= r_pll;

    case r_pll.state is
      when ST_RESET =>
        rin_pll.pll_count <= 0;
        rin_pll.pll_pd    <= '1';
        rin_pll.pll_done  <= '0';
        rin_pll.state     <= ST_HOLD_RST;
      when ST_HOLD_RST =>
        rin_pll.pll_count <= r_pll.pll_count + 1;
        rin_pll.pll_pd    <= '1';
        if r_pll.pll_count = hold_delay_c then
          rin_pll.state <= ST_WAIT_PWR_GOOD;
        end if;
      when ST_WAIT_PWR_GOOD =>
        if power_good_i = '1' then
          rin_pll.state <= ST_DONE;
        end if;
      when ST_DONE =>
        rin_pll.pll_pd   <= '0';
        rin_pll.pll_done <= '1';
    end case;

  end process;

end architecture;
