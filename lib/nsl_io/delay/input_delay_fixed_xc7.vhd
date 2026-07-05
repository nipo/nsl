library ieee;
use ieee.std_logic_1164.all;

entity input_delay_fixed is
  generic(
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture xc7 of input_delay_fixed is

  attribute BOX_TYPE : string;

  component IDELAYE2
    generic (
      CINVCTRL_SEL : string := "FALSE";
      DELAY_SRC : string := "IDATAIN";
      HIGH_PERFORMANCE_MODE : string := "FALSE";
      IDELAY_TYPE : string := "FIXED";
      IDELAY_VALUE : integer := 0;
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
      CNTVALUEIN : in std_logic_vector(4 downto 0);
      DATAIN : in std_ulogic;
      IDATAIN : in std_ulogic;
      INC : in std_ulogic;
      LD : in std_ulogic;
      LDPIPEEN : in std_ulogic;
      REGRST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IDELAYE2 : component is "PRIMITIVE";

  constant ref_freq : real := 200.0e6;
  constant tap_delay_ps_c : integer := integer(1.0e12 / 32.0 / 2.0 / ref_freq);
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: idelaye2
      generic map(
        delay_src => "IDATAIN",
        idelay_type => "FIXED",
        idelay_value => tap_count_i,
        refclk_frequency => ref_freq / 1.0e6
        )
      port map(
        c => '0',
        ce => '0',
        cinvctrl => '0',
        cntvaluein => "00000",
        datain => '0',
        dataout => data_o,
        idatain => data_i,
        inc => '0',
        ld => '0',
        ldpipeen => '0',
        regrst => '0'
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end architecture;
