library ieee;
use ieee.std_logic_1164.all;

library nsl_data;

entity serdes_output is
  generic(
    left_first_c : boolean := false;
    ddr_mode_c : boolean := false;
    to_delay_c : boolean := false;
    ratio_c : positive
    );
  port(
    serial_clock_i : in std_ulogic;
    parallel_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    parallel_i : in std_ulogic_vector(0 to ratio_c-1);
    serial_o : out std_ulogic
    );
end entity;

architecture series6 of serdes_output is

  attribute BOX_TYPE : string;

  component OSERDES2
    generic (
      BYPASS_GCLK_FF : boolean := FALSE;
      DATA_RATE_OQ : string := "DDR";
      DATA_RATE_OT : string := "DDR";
      DATA_WIDTH : integer := 2;
      OUTPUT_MODE : string := "SINGLE_ENDED";
      SERDES_MODE : string := "NONE";
      TRAIN_PATTERN : integer := 0
      );
    port (
      OQ : out std_ulogic;
      SHIFTOUT1 : out std_ulogic;
      SHIFTOUT2 : out std_ulogic;
      SHIFTOUT3 : out std_ulogic;
      SHIFTOUT4 : out std_ulogic;
      TQ : out std_ulogic;
      CLK0 : in std_ulogic;
      CLK1 : in std_ulogic;
      CLKDIV : in std_ulogic;
      D1 : in std_ulogic;
      D2 : in std_ulogic;
      D3 : in std_ulogic;
      D4 : in std_ulogic;
      IOCE : in std_ulogic := 'H';
      OCE : in std_ulogic := 'H';
      RST : in std_ulogic;
      SHIFTIN1 : in std_ulogic;
      SHIFTIN2 : in std_ulogic;
      SHIFTIN3 : in std_ulogic;
      SHIFTIN4 : in std_ulogic;
      T1 : in std_ulogic;
      T2 : in std_ulogic;
      T3 : in std_ulogic;
      T4 : in std_ulogic;
      TCE : in std_ulogic;
      TRAIN : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    OSERDES2 : component is "PRIMITIVE";

  constant data_rate_c: string := nsl_data.text.if_else(ddr_mode_c, "DDR", "SDR");
  constant cascade_needed_c: boolean := ratio_c > 4;
  constant master_mode_c: string := nsl_data.text.if_else(cascade_needed_c, "MASTER", "NONE");
  signal cascade1_s, cascade2_s, cascade3_s, cascade4_s,
    reset_s, serial_clock_n_s : std_ulogic;
  -- left to right
  signal tx_data_s: std_ulogic_vector(0 to 7) := (others => '0');

begin

  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;

  assert ((ratio_c >= 2) and (ratio_c <= 8))
    report "Only support ratio in range 2:8"
    severity failure;

  reset_s <= not reset_n_i;

  feeder: process(parallel_i) is
  begin
    for i in 0 to ratio_c-1
    loop
      if left_first_c then
        tx_data_s(i) <= parallel_i(i);
      else
        tx_data_s(i) <= parallel_i(ratio_c-1-i);
      end if;
    end loop;
  end process;

  serial_clock_n_s <= not serial_clock_i;
  
  master: oserdes2
    generic map(
      data_rate_oq => data_rate_c,
      data_rate_ot => data_rate_c,
      data_width => ratio_c,
      serdes_mode => master_mode_c
      )
    port map(
      oq => serial_o,
      clk0 => serial_clock_i,
      clk1 => serial_clock_n_s,
      clkdiv => parallel_clock_i,
      d1 => tx_data_s(0),
      d2 => tx_data_s(1),
      d3 => tx_data_s(2),
      d4 => tx_data_s(3),
      ioce => '1',
      oce => '1',
      rst => reset_s,
      shiftin1 => cascade1_s,
      shiftin2 => cascade2_s,
      shiftin3 => cascade3_s,
      shiftin4 => cascade4_s,
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0',
      tce => '0',
      train => '0'
      );

  has_slave: if cascade_needed_c
  generate
    slave: oserdes2
      generic map(
        data_rate_oq => data_rate_c,
        data_rate_ot => data_rate_c,
        data_width => ratio_c,
        serdes_mode => "SLAVE"
        )
      port map (
        shiftout1 => cascade1_s,
        shiftout2 => cascade2_s,
        shiftout3 => cascade3_s,
        shiftout4 => cascade4_s,
        clk0 => serial_clock_i,
        clk1 => serial_clock_n_s,
        clkdiv => parallel_clock_i,
        d1 => tx_data_s(4),
        d2 => tx_data_s(5),
        d3 => tx_data_s(6),
        d4 => tx_data_s(7),
        ioce => '1',
        oce => '1',
        rst => reset_s,
        shiftin1 => '0',
        shiftin2 => '0',
        shiftin3 => '0',
        shiftin4 => '0',
        t1 => '0',
        t2 => '0',
        t3 => '0',
        t4 => '0',
        tce => '0',
        train => '0'
        );
  end generate;
    
end architecture;
