library ieee;
use ieee.std_logic_1164.all;

-- Reset sequencer for a GTPE2 channel.
--
-- Waits for the PLL, pulses the channel reset and, around the PMA reset
-- cycle, performs a read-modify-write of the channel DRP register at
-- address 0x011: bit 11 is cleared for the duration of the PMA reset
-- and the original value is restored afterwards. The sequence restarts
-- if it stalls for timeout_delay_c cycles.
--
-- All inputs must already be synchronous to clock_i (the DRP clock).
entity gtpe2_reset_fsm is
  generic(
    -- Stall watchdog, in clock_i cycles
    timeout_delay_c : natural
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    pll_locked_i     : in std_ulogic;
    pll_reset_done_i : in std_ulogic;
    pma_rst_done_i   : in std_ulogic;

    gtp_rst_o : out std_ulogic;

    -- DRP master, to be connected to the channel DRP port
    drp_addr_o  : out std_ulogic_vector(8 downto 0);
    drp_en_o    : out std_ulogic;
    drp_wr_o    : out std_ulogic;
    drp_wdata_o : out std_ulogic_vector(15 downto 0);
    drp_rdata_i : in  std_ulogic_vector(15 downto 0);
    drp_rdy_i   : in  std_ulogic
    );
end entity;

architecture beh of gtpe2_reset_fsm is

  type reset_state_t is (
    ST_RESET,
    ST_WAIT_PLL,
    ST_WAIT_PMA_LOW,
    ST_READ_DRP,
    ST_READ_WAIT,
    ST_WRITE_DRP,
    ST_WRITE_WAIT,
    ST_WAIT_PMA_LOW2,
    ST_WAIT_PMA_HIGH,
    ST_WAIT_PMA_FALL,
    ST_RESTORE_DRP,
    ST_RESTORE_WAIT,
    ST_DONE);

  type regs_t is
  record
    state   : reset_state_t;
    gtp_rst : std_ulogic;
    drp_en  : std_ulogic;
    drp_wr  : std_ulogic;
    drp_val : std_ulogic_vector(15 downto 0);
    drp_out : std_ulogic_vector(15 downto 0);
    timeout : natural;
  end record;

  signal r, rin : regs_t;

begin

  gtp_rst_o   <= r.gtp_rst;
  drp_wdata_o <= r.drp_out;
  drp_addr_o  <= B"000010001";
  drp_en_o    <= r.drp_en;
  drp_wr_o    <= r.drp_wr;

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

  transition : process(r, drp_rdata_i, drp_rdy_i, pll_locked_i,
                       pll_reset_done_i, pma_rst_done_i) is

  begin
    rin         <= r;
    rin.timeout <= r.timeout - 1;

    case r.state is
      when ST_RESET =>
        rin.state   <= ST_WAIT_PLL;
        rin.gtp_rst <= '0';
        rin.drp_en  <= '0';
        rin.drp_wr  <= '0';
        rin.drp_val <= (others => '0');
        rin.drp_out <= (others => '0');
        rin.timeout <= timeout_delay_c;
      when ST_WAIT_PLL =>
        rin.gtp_rst <= '0';
        if pll_locked_i = '1' and pll_reset_done_i = '1' then
          rin.state <= ST_WAIT_PMA_LOW;
        end if;
      when ST_WAIT_PMA_LOW =>
        rin.gtp_rst <= '1';
        if pma_rst_done_i = '0' then
          rin.state <= ST_READ_DRP;
        end if;
      when ST_READ_DRP =>
        rin.drp_en <= '1';
        rin.drp_wr <= '0';
        rin.state  <= ST_READ_WAIT;
      when ST_READ_WAIT =>
        rin.drp_en <= '0';
        rin.drp_wr <= '0';
        if drp_rdy_i = '1' then
          rin.drp_val <= drp_rdata_i;
          rin.state   <= ST_WRITE_DRP;
        end if;
      when ST_WRITE_DRP =>
        rin.drp_en  <= '1';
        rin.drp_wr  <= '1';
        rin.drp_out <= r.drp_val(15 downto 12) & '0' & r.drp_val(10 downto 0);
        rin.state   <= ST_WRITE_WAIT;
      when ST_WRITE_WAIT =>
        rin.drp_en <= '0';
        rin.drp_wr <= '0';
        if drp_rdy_i = '1' then
          rin.state <= ST_WAIT_PMA_LOW2;
        end if;
      when ST_WAIT_PMA_LOW2 =>
        rin.drp_en  <= '0';
        rin.drp_wr  <= '0';
        rin.gtp_rst <= '0';
        if pma_rst_done_i = '0' then
          rin.state <= ST_WAIT_PMA_HIGH;
        end if;
      when ST_WAIT_PMA_HIGH =>
        if pma_rst_done_i = '1' then
          rin.state <= ST_WAIT_PMA_FALL;
        end if;
      when ST_WAIT_PMA_FALL =>
        if pma_rst_done_i = '0' then
          rin.state <= ST_RESTORE_DRP;
        end if;
      when ST_RESTORE_DRP =>
        rin.drp_en  <= '1';
        rin.drp_wr  <= '1';
        rin.drp_out <= r.drp_val;
        rin.state   <= ST_RESTORE_WAIT;
      when ST_RESTORE_WAIT =>
        rin.drp_en <= '0';
        rin.drp_wr <= '0';
        if drp_rdy_i = '1' then
          rin.state <= ST_DONE;
        end if;
      when ST_DONE =>
        rin.drp_en  <= '0';
        rin.drp_wr  <= '0';
        rin.timeout <= timeout_delay_c;
    end case;

  end process;

end architecture;
