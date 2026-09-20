library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_io;

entity serdes_output_tristated is
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
    output_enable_i : in std_ulogic_vector(0 to ratio_c/2-1);

    pad_o : out nsl_io.io.tristated
    );
end entity;

architecture series7 of serdes_output_tristated is

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

  signal reset_s, off_s : std_ulogic;
  -- left to right, whatever the direction the caller passed
  signal tx_data_s: std_ulogic_vector(0 to 7);
  signal tx_off_s: std_ulogic;

begin

  -- **This family turns a pin around once a word, not once a pair.**
  -- Its pad logic will carry four tristate registers only for a
  -- serialiser four bits wide; at eight it takes one, shifted at
  -- single rate and so held for the whole word.  The interface asks
  -- for a bit per pair because that is the finest any family here
  -- offers, so what arrives is reduced: the pin is driven for the
  -- whole word if any pair of it asks.
  --
  -- A pad is therefore held past what was asked for, never released
  -- early.  A bus whose turnaround has to happen inside a word cannot
  -- use this, and a design sharing a bus with another driver has to
  -- know which way its family rounds.
  assert ddr_mode_c and ratio_c = 8
    report "Tristated serdes output on this family is eight bits at double rate"
    severity failure;

  reset_s <= not reset_n_i;
  -- The primitive says when to let go of the pin; the pad type says
  -- when to hold it.
  pad_o.en <= not off_s;

  feeder: process(parallel_i, output_enable_i) is
  begin
    for i in 0 to ratio_c-1
    loop
      if left_first_c then
        tx_data_s(i) <= parallel_i(i);
      else
        tx_data_s(i) <= parallel_i(ratio_c-1-i);
      end if;
    end loop;

    tx_off_s <= '1';
    for i in 0 to ratio_c/2-1
    loop
      if output_enable_i(i) = '1' then
        tx_off_s <= '0';
      end if;
    end loop;
  end process;

  master: oserdese2
    generic map(
      data_rate_oq => "DDR",
      -- Single rate rather than buffered: buffered hands the pad its
      -- tristate straight from the fabric while the data it belongs
      -- to travels the serialiser's pipeline, so the pin is released
      -- on the cycle the word it was meant to carry reaches it.  A
      -- bus driven that way holds a constant and never carries its
      -- burst, which on a memory strobe reads as a pin nobody drives.
      data_rate_tq => "SDR",
      data_width => ratio_c,
      serdes_mode => "MASTER",
      -- Held off at reset, so a bus is let go of rather than fought over
      init_tq => '1',
      srval_tq => '1',
      tristate_width => 1
      )
    port map(
      oq => pad_o.v,
      tq => off_s,
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
      t1 => tx_off_s,
      t2 => '1',
      t3 => '1',
      t4 => '1',
      tce => '1',
      oce => '1',
      tbytein => '0',
      rst => reset_s,
      shiftin1 => '0',
      shiftin2 => '0'
      );

end architecture;
