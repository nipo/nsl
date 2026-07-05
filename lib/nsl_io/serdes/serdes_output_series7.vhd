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

architecture series7 of serdes_output is

  attribute BOX_TYPE : string;

  component OSERDESE2
    generic (
      DATA_RATE_OQ : string := "DDR";
      DATA_RATE_TQ : string := "DDR";
      DATA_WIDTH : integer := 4;
      INIT_OQ : bit := '0';
      INIT_TQ : bit := '0';
      SERDES_MODE : string := "MASTER";
      SRVAL_OQ : bit := '0';
      SRVAL_TQ : bit := '0';
      TBYTE_CTL : string := "FALSE";
      TBYTE_SRC : string := "FALSE";
      TRISTATE_WIDTH : integer := 4
      );
    port (
      OFB : out std_ulogic;
      OQ : out std_ulogic;
      SHIFTOUT1 : out std_ulogic;
      SHIFTOUT2 : out std_ulogic;
      TBYTEOUT : out std_ulogic;
      TFB : out std_ulogic;
      TQ : out std_ulogic;
      CLK : in std_ulogic;
      CLKDIV : in std_ulogic;
      D1 : in std_ulogic;
      D2 : in std_ulogic;
      D3 : in std_ulogic;
      D4 : in std_ulogic;
      D5 : in std_ulogic;
      D6 : in std_ulogic;
      D7 : in std_ulogic;
      D8 : in std_ulogic;
      OCE : in std_ulogic;
      RST : in std_ulogic;
      SHIFTIN1 : in std_ulogic;
      SHIFTIN2 : in std_ulogic;
      T1 : in std_ulogic;
      T2 : in std_ulogic;
      T3 : in std_ulogic;
      T4 : in std_ulogic;
      TBYTEIN : in std_ulogic;
      TCE : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    OSERDESE2 : component is "PRIMITIVE";

  constant data_rate_c: string := nsl_data.text.if_else(ddr_mode_c, "DDR", "SDR");
  constant cascade_needed_c: boolean := ratio_c > 8;
  signal cascade1_s, cascade2_s, reset_s : std_ulogic;
  -- left to right
  signal tx_data_s: std_ulogic_vector(0 to 13) := (others => '0');

begin

  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;

  assert ddr_mode_c or ((ratio_c >= 2) and (ratio_c <= 8))
    report "SDR mode only support ratio in range 2:8"
    severity failure;

  assert (not ddr_mode_c) or ((ratio_c >= 4) and (ratio_c <= 14) and (ratio_c /= 12))
    report "DDR can only support ratio in 4,6,8,10,14"
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

  master: oserdese2
    generic map(
      data_rate_oq => data_rate_c,
      data_rate_tq => "SDR",
      data_width => ratio_c,
      serdes_mode => "MASTER",
      tristate_width => 1
      )
    port map(
      oq => serial_o,
      clk => serial_clock_i,
      clkdiv => parallel_clock_i,
      d1 => tx_data_s(0),
      d2 => tx_data_s(1),
      d3 => tx_data_s(2),
      d4 => tx_data_s(3),
      d5 => tx_data_s(4),
      d6 => tx_data_s(5),
      d7 => tx_data_s(6),
      d8 => tx_data_s(7),
      tce => '0',
      oce => '1',
      tbytein => '0',
      rst => reset_s,
      shiftin1 => cascade1_s,
      shiftin2 => cascade2_s,
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0'
      );

  has_slave: if cascade_needed_c
  generate
    slave: oserdese2
      generic map(
        data_rate_oq => data_rate_c,
        data_rate_tq => "SDR",
        data_width => ratio_c,
        serdes_mode => "SLAVE",
        tristate_width => 1
        )
      port map (
        shiftout1 => cascade1_s,
        shiftout2 => cascade2_s,
        clk => serial_clock_i,
        clkdiv => parallel_clock_i,
        d1 => '0',
        d2 => '0',
        d3 => tx_data_s(8),
        d4 => tx_data_s(9),
        d5 => tx_data_s(10),
        d6 => tx_data_s(11),
        d7 => tx_data_s(12),
        d8 => tx_data_s(13),
        tce => '0',
        oce => '1',
        tbytein => '0',
        rst => reset_s,
        shiftin1 => '0',
        shiftin2 => '0',
        t1 => '0',
        t2 => '0',
        t3 => '0',
        t4 => '0'
        );
  end generate;
    
end architecture;
