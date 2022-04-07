library ieee;
use ieee.std_logic_1164.all;

library unisim, nsl_hwdep;

entity output_delay_variable is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    mark_o : out std_ulogic;
    shift_i : in std_ulogic;

    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture xc6 of output_delay_variable is

  constant tap_delay_ps_c : integer := nsl_hwdep.xc6_config.iodelay2_tap_ps;
  constant tap_step_count_c : integer := 256;
  signal step_count_s: integer range 0 to tap_step_count_c-1;
  signal reset_s: std_ulogic;

begin

  reset_s <= not reset_n_i;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if shift_i = '1' then
        if step_count_s = 0 then
          step_count_s <= tap_step_count_c-1;
        else
          step_count_s <= step_count_s - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      step_count_s <= 0;
    end if;
  end process;

  mark_o <= '1' when step_count_s = 0 else '0';

  inst: unisim.vcomponents.iodelay2
    generic map(
      data_rate => "DDR",
      delay_src => "ODATAIN",
      idelay_type => "VARIABLE_FROM_ZERO",
      idelay_value => 0,
      idelay2_value => 0,
      odelay_value => 0,
      serdes_mode => "NONE",
      sim_tapdelay_value => tap_delay_ps_c
      )
    port map(
      cal => '0',
      ce => shift_i,
      clk => clock_i,
      odatain => data_i,
      idatain => '0',
      inc => '0',
      ioclk0 => '0',
      ioclk1 => '0',
      dout => data_o,
      rst => reset_s,
      t => '0'
      );
  
end architecture;
