library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim, nsl_hwdep;

entity input_delay_variable_sdr is
  port (
    clock_i     : in  std_ulogic;
    bit_clock_i : in  std_ulogic;
    reset_n_i   : in  std_ulogic;
    mark_o      : out std_ulogic;
    shift_i     : in  std_ulogic;

    data_i : in  std_ulogic;
    data_o : out std_ulogic
  );
end entity;

architecture xc6 of input_delay_variable_sdr is

  constant tap_delay_ps_c   : integer := nsl_hwdep.xc6_config.iodelay2_tap_ps;
  constant tap_step_count_c : integer := 256;
  signal step_count_s       : integer range 0 to tap_step_count_c - 1;

  signal reset_s : std_ulogic;

  -- IODELAY2 control / status
  signal busy_s : std_ulogic;
  signal cal_s  : std_ulogic;
  signal rst_s  : std_ulogic;
  signal ce_s   : std_ulogic;

  -- small calibration FSM
  type cal_state_t is (S_IDLE, S_CAL_PULSE, S_WAIT_BUSY_HI, S_WAIT_BUSY_LO, S_RST_PULSE, S_DONE);
  signal cal_state_s : cal_state_t;

begin

  reset_s <= not reset_n_i;

  regs : process (clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if shift_i = '1' then
        if step_count_s = 0 then
          step_count_s <= tap_step_count_c - 1;
        else
          step_count_s <= step_count_s - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      step_count_s <= 0;
    end if;
  end process;

  mark_o <= '1' when step_count_s = 0 else
            '0';

  cal_fsm : process (clock_i, reset_s)
  begin
    if rising_edge(clock_i) then
      cal_s <= '0';
      rst_s <= '0';

      case cal_state_s is
        when S_IDLE =>
          cal_state_s <= S_CAL_PULSE;

        when S_CAL_PULSE =>
          cal_s       <= '1';
          cal_state_s <= S_WAIT_BUSY_HI;

        when S_WAIT_BUSY_HI =>
          if busy_s = '1' then
            cal_state_s <= S_WAIT_BUSY_LO;
          end if;

        when S_WAIT_BUSY_LO =>
          if busy_s = '0' then
            cal_state_s <= S_RST_PULSE;
          end if;

        when S_RST_PULSE =>
          rst_s       <= '1';
          cal_state_s <= S_DONE;

        when S_DONE =>
          cal_state_s <= S_DONE;

        when others =>
          cal_state_s <= S_IDLE;
      end case;
    end if;

    if reset_s = '1' then
      cal_state_s <= S_IDLE;
      cal_s       <= '0';
      rst_s       <= '0';
    end if;
  end process;

  ce_s <= shift_i when cal_state_s = S_DONE else
          '0';

  inst : unisim.vcomponents.iodelay2
  generic map(
    data_rate          => "SDR",
    delay_src          => "IDATAIN",
    idelay_type        => "VARIABLE_FROM_ZERO",
    idelay_value       => 0,
    idelay2_value      => 0,
    odelay_value       => 0,
    serdes_mode        => "NONE",
    sim_tapdelay_value => tap_delay_ps_c,
    counter_wraparound => "WRAPAROUND"
  )
  port map(
    cal     => cal_s,
    ce      => ce_s,
    clk     => clock_i,
    odatain => '0',
    idatain => data_i,
    inc     => '0',
    ioclk0  => bit_clock_i,
    ioclk1  => '0',
    dataout => data_o,
    rst     => rst_s,
    busy    => busy_s,
    t       => '1'
  );

end architecture;
