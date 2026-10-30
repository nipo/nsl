library ieee;
use ieee.std_logic_1164.all;

-- Reset sequencer for one direction (RX or TX) of a GTHE4 channel.
--
-- Holds the channel reset until the PLL is locked, the PMA reset-done
-- signal has dropped, the transceiver power is good and a settling delay
-- has elapsed; then releases it, waits for the PMA and the channel
-- reset-done and finally raises ready. The sequence restarts if it stalls
-- for timeout_delay_c cycles or if the PLL loses lock.
--
-- All inputs must already be synchronous to clock_i.
entity gthe4_reset_fsm is
  generic(
    -- Stall watchdog, in clock_i cycles
    timeout_delay_c : natural;
    -- Settling delay after power good, in clock_i cycles
    gt_pwr_delay_c  : natural
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    power_good_i     : in std_ulogic;
    pll_locked_i     : in std_ulogic;
    pll_reset_done_i : in std_ulogic;
    pma_rst_done_i   : in std_ulogic;
    rst_done_i       : in std_ulogic;

    gth_rst_o : out std_ulogic;
    ready_o   : out std_ulogic
    );
end entity;

architecture beh of gthe4_reset_fsm is

  type reset_state_t is (
    ST_RESET,
    ST_WAIT_PLL,
    ST_WAIT_PMA_LOW,
    ST_WAIT_PWR_GOOD,
    ST_DELAY_PWR_GOOD,
    ST_WAIT_PMA_HIGH,
    ST_READY,
    ST_DONE);

  type regs_t is
  record
    state     : reset_state_t;
    gth_rst   : std_ulogic;
    timeout   : natural;
    pwr_timer : natural;
    ready     : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  gth_rst_o <= r.gth_rst;
  ready_o   <= r.ready;

  reg : process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
      if r.timeout = 0 then
        r.state <= ST_RESET;
      end if;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition : process(r, power_good_i, pll_locked_i, pll_reset_done_i,
                       pma_rst_done_i, rst_done_i) is

  begin
    rin         <= r;
    rin.timeout <= r.timeout - 1;

    case r.state is
      when ST_RESET =>
        rin.state   <= ST_WAIT_PLL;
        rin.gth_rst <= '1';
        rin.timeout <= timeout_delay_c;
        rin.ready   <= '0';
      when ST_WAIT_PLL =>
        rin.gth_rst <= '1';
        if pll_locked_i = '1' and pll_reset_done_i = '1' then
          rin.state <= ST_WAIT_PMA_LOW;
        end if;
      when ST_WAIT_PMA_LOW =>
        if pma_rst_done_i = '0' then
          rin.state <= ST_WAIT_PWR_GOOD;
        end if;
      when ST_WAIT_PWR_GOOD =>
        rin.pwr_timer <= gt_pwr_delay_c;
        if power_good_i = '1' then
          rin.state <= ST_DELAY_PWR_GOOD;
        end if;
      when ST_DELAY_PWR_GOOD =>
        if r.pwr_timer = 0 then
          rin.state <= ST_WAIT_PMA_HIGH;
        else
          rin.pwr_timer <= r.pwr_timer - 1;
        end if;
      when ST_WAIT_PMA_HIGH =>
        rin.gth_rst <= '0';
        if pma_rst_done_i = '1' then
          rin.state <= ST_READY;
        end if;
      when ST_READY =>
        rin.ready <= '1';
        if rst_done_i = '1' then
          rin.state <= ST_DONE;
        end if;
      when ST_DONE =>
        rin.timeout <= timeout_delay_c;
        if pll_locked_i = '0' then
          rin.state <= ST_RESET;
        end if;
    end case;

  end process;

end architecture;
