library ieee;
use ieee.std_logic_1164.all;

entity serdes_ddr10_output is
  generic(
    left_to_right_c : boolean := false
    );
  port(
    bit_clock_i : in std_ulogic;
    word_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    parallel_i : in std_ulogic_vector(0 to 9);
    serial_o : out std_ulogic
    );
end entity;

architecture series7 of serdes_ddr10_output is

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

  signal cascade1, cascade2, reset : std_ulogic;
  signal d: std_ulogic_vector(0 to 9);

begin

  reset <= not reset_n_i;

  ltr: if left_to_right_c
  generate
    d <= parallel_i;
  end generate;

  rtl: if not left_to_right_c
  generate
    in_map: for i in 0 to 9
    generate
      d(9-i) <= parallel_i(i);
    end generate;
  end generate;


  master: oserdese2
    generic map(
      data_rate_oq => "DDR",
      data_rate_tq => "SDR",
      data_width => 10,
      serdes_mode => "MASTER",
      tristate_width => 1
      )
    port map(
      oq => serial_o,
      clk => bit_clock_i,
      clkdiv => word_clock_i,
      d1 => d(0),
      d2 => d(1),
      d3 => d(2),
      d4 => d(3),
      d5 => d(4),
      d6 => d(5),
      d7 => d(6),
      d8 => d(7),
      tce => '0',
      oce => '1',
      tbytein => '0',
      rst => reset,
      shiftin1 => cascade1,
      shiftin2 => cascade2,
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0'
      );

  slave: oserdese2
    generic map(
      data_rate_oq => "DDR",
      data_rate_tq => "SDR",
      data_width => 10,
      serdes_mode => "SLAVE",
      tristate_width => 1
      )
    port map (
      shiftout1 => cascade1,
      shiftout2 => cascade2,
      clk => bit_clock_i,
      clkdiv => word_clock_i,
      d1 => '0',
      d2 => '0',
      d3 => d(8),
      d4 => d(9),
      d5 => '0',
      d6 => '0',
      d7 => '0',
      d8 => '0',
      tce => '0',
      oce => '1',
      tbytein => '0',
      rst => reset,
      shiftin1 => '0',
      shiftin2 => '0',
      t1 => '0',
      t2 => '0',
      t3 => '0',
      t4 => '0'
      );

end architecture;
