library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig;

entity input_delay_variable is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    mark_o : out std_ulogic;
    shift_i : in std_ulogic;

    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture xc6 of input_delay_variable is

  attribute BOX_TYPE : string;

  component IODELAY2
    generic (
      COUNTER_WRAPAROUND : string := "WRAPAROUND";
      DATA_RATE : string := "SDR";
      DELAY_SRC : string := "IO";
      IDELAY2_VALUE : integer := 0;
      IDELAY_MODE : string := "NORMAL";
      IDELAY_TYPE : string := "DEFAULT";
      IDELAY_VALUE : integer := 0;
      ODELAY_VALUE : integer := 0;
      SERDES_MODE : string := "NONE";
      SIM_TAPDELAY_VALUE : integer := 75
      );
    port (
      BUSY : out std_ulogic;
      DATAOUT : out std_ulogic;
      DATAOUT2 : out std_ulogic;
      DOUT : out std_ulogic;
      TOUT : out std_ulogic;
      CAL : in std_ulogic;
      CE : in std_ulogic;
      CLK : in std_ulogic;
      IDATAIN : in std_ulogic;
      INC : in std_ulogic;
      IOCLK0 : in std_ulogic;
      IOCLK1 : in std_ulogic;
      ODATAIN : in std_ulogic;
      RST : in std_ulogic;
      T : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IODELAY2 : component is "PRIMITIVE";

  constant tap_delay_ps_c : integer := nsl_hwconfig.xc6_config.iodelay2_tap_ps;
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

  inst: iodelay2
    generic map(
      data_rate => "DDR",
      delay_src => "IDATAIN",
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
      odatain => '0',
      idatain => data_i,
      inc => '0',
      ioclk0 => '0',
      ioclk1 => '0',
      dataout => data_o,
      rst => reset_s,
      t => '0'
      );
  
end architecture;
