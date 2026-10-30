library ieee;
use ieee.std_logic_1164.all;

-- Reset sequencer for the shared PLLs of a GTPE2 common block.
--
-- Holds the PLLs powered down for 500ns, powers them up, waits another
-- 500ns, then pulses the PLL reset for delay_pll_rst_c cycles and
-- reports done.
entity gtpe2_pll_reset_fsm is
  generic(
    -- 500ns (plus margin) in clock_i cycles
    delay500ns_c    : natural;
    -- A few clock cycles for PLL reset
    delay_pll_rst_c : natural := 5
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    pll_pd_o  : out std_ulogic;
    pll_rst_o : out std_ulogic;
    done_o    : out std_ulogic
    );
end entity;

architecture beh of gtpe2_pll_reset_fsm is

  type reset_state_t is (
    ST_RESET,
    ST_WAIT_500,
    ST_WAIT_1000,
    ST_HOLD_RST,
    ST_DONE);

  type regs_t is
  record
    state     : reset_state_t;
    pll_count : natural;
    pll_pd    : std_ulogic;
    pll_rst   : std_ulogic;
    pll_done  : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  pll_rst_o <= r.pll_rst;
  pll_pd_o  <= r.pll_pd;
  done_o    <= r.pll_done;

  reg : process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition : process(r) is

  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.pll_count <= 0;
        rin.pll_pd    <= '1';
        rin.pll_rst   <= '0';
        rin.pll_done  <= '0';
        rin.state     <= ST_WAIT_500;
      when ST_WAIT_500 =>
        rin.pll_count <= r.pll_count + 1;
        if r.pll_count = delay500ns_c then
          rin.state <= ST_WAIT_1000;
        end if;
      when ST_WAIT_1000 =>
        rin.pll_count <= r.pll_count + 1;
        rin.pll_pd    <= '0';
        if r.pll_count = delay500ns_c * 2 then
          rin.state <= ST_HOLD_RST;
        end if;
      when ST_HOLD_RST =>
        rin.pll_count <= r.pll_count + 1;
        rin.pll_rst   <= '1';
        if r.pll_count = (delay500ns_c * 2) + delay_pll_rst_c then
          rin.state <= ST_DONE;
        end if;
      when ST_DONE =>
        rin.pll_rst  <= '0';
        rin.pll_done <= '1';
    end case;

  end process;

end architecture;
