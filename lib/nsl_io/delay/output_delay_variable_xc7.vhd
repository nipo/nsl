library ieee;
use ieee.std_logic_1164.all;

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

architecture xc7 of output_delay_variable is

  attribute BOX_TYPE : string;

  component ODELAYE2
    generic (
      CINVCTRL_SEL : string := "FALSE";
      DELAY_SRC : string := "ODATAIN";
      HIGH_PERFORMANCE_MODE : string := "FALSE";
      ODELAY_TYPE : string := "FIXED";
      ODELAY_VALUE : integer := 0;
      PIPE_SEL : string := "FALSE";
      REFCLK_FREQUENCY : real := 200.0;
      SIGNAL_PATTERN : string := "DATA"
      );
    port (
      CNTVALUEOUT : out std_logic_vector(4 downto 0);
      DATAOUT : out std_ulogic;
      C : in std_ulogic;
      CE : in std_ulogic;
      CINVCTRL : in std_ulogic;
      CLKIN : in std_ulogic;
      CNTVALUEIN : in std_logic_vector(4 downto 0);
      INC : in std_ulogic;
      LD : in std_ulogic;
      LDPIPEEN : in std_ulogic;
      ODATAIN : in std_ulogic;
      REGRST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    ODELAYE2 : component is "PRIMITIVE";

  constant ref_freq : real := 200.0e6;
  constant tap_step_count_c : integer := 32;
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
  
  inst: odelaye2
    generic map(
      delay_src => "ODATAIN",
      odelay_type => "VARIABLE",
      odelay_value => 0,
      pipe_sel => "FALSE",
      signal_pattern => "DATA",
      refclk_frequency => ref_freq / 1.0e6
      )
    port map(
      c => clock_i,
      ce => shift_i,
      cinvctrl => '0',
      clkin => '0',
      cntvaluein => "00000",
      dataout => data_o,
      inc => '0',
      ld => '0',
      ldpipeen => '0',
      odatain => data_i,
      regrst => '0'
      );
  
end architecture;
