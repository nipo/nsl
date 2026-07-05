library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;

entity serdes_ddr10_input is
  generic(
    left_to_right_c : boolean := false
    );
  port(
    bit_clock_i : in std_ulogic;
    word_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    serial_i : in std_ulogic;
    parallel_o : out std_ulogic_vector(0 to 9);

    bitslip_i : in std_ulogic;
    mark_o : out std_ulogic
    );
end entity;

architecture series7 of serdes_ddr10_input is

  attribute BOX_TYPE : string;

  component ISERDESE2
    generic (
      DATA_RATE : string := "DDR";
      DATA_WIDTH : integer := 4;
      DYN_CLKDIV_INV_EN : string := "FALSE";
      DYN_CLK_INV_EN : string := "FALSE";
      INIT_Q1 : bit := '0';
      INIT_Q2 : bit := '0';
      INIT_Q3 : bit := '0';
      INIT_Q4 : bit := '0';
      INTERFACE_TYPE : string := "MEMORY";
      IOBDELAY : string := "NONE";
      NUM_CE : integer := 2;
      OFB_USED : string := "FALSE";
      SERDES_MODE : string := "MASTER";
      SRVAL_Q1 : bit := '0';
      SRVAL_Q2 : bit := '0';
      SRVAL_Q3 : bit := '0';
      SRVAL_Q4 : bit := '0'
      );
    port (
      O : out std_ulogic;
      Q1 : out std_ulogic;
      Q2 : out std_ulogic;
      Q3 : out std_ulogic;
      Q4 : out std_ulogic;
      Q5 : out std_ulogic;
      Q6 : out std_ulogic;
      Q7 : out std_ulogic;
      Q8 : out std_ulogic;
      SHIFTOUT1 : out std_ulogic;
      SHIFTOUT2 : out std_ulogic;
      BITSLIP : in std_ulogic;
      CE1 : in std_ulogic;
      CE2 : in std_ulogic;
      CLK : in std_ulogic;
      CLKB : in std_ulogic;
      CLKDIV : in std_ulogic;
      CLKDIVP : in std_ulogic;
      D : in std_ulogic;
      DDLY : in std_ulogic;
      DYNCLKDIVSEL : in std_ulogic;
      DYNCLKSEL : in std_ulogic;
      OCLK : in std_ulogic;
      OCLKB : in std_ulogic;
      OFB : in std_ulogic;
      RST : in std_ulogic;
      SHIFTIN1 : in std_ulogic;
      SHIFTIN2 : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    ISERDESE2 : component is "PRIMITIVE";

  constant from_delay_c: boolean := true;
  constant iobdelay_c: string := nsl_data.text.if_else(from_delay_c, "BOTH", "NONE");
  signal cascade1, cascade2, reset_s, bit_clock_n_s : std_ulogic;
  signal d: std_ulogic_vector(0 to 9);
  signal slip_count: integer range 0 to 9;
  signal d_i, ddly_i: std_ulogic;

begin

  reset_s <= not reset_n_i;

  is_from_delay: if from_delay_c
  generate
    d_i <= '0';
    ddly_i <= serial_i;
  end generate;
  
  is_from_pin: if not from_delay_c
  generate
    d_i <= serial_i;
    ddly_i <= '0';
  end generate;
  
  output: process(d) is
  begin
    if not left_to_right_c then
      parallel_o <= d;
    else
      for i in 0 to 9
      loop
        parallel_o(9-i) <= d(i);
      end loop;
    end if;
  end process;

  bit_clock_n_s <= not bit_clock_i;

  slip_tracker: process(word_clock_i, reset_n_i) is
  begin
    if rising_edge(word_clock_i) then
      if bitslip_i = '1' then
        if slip_count = 0 then
          slip_count <= 9;
        else
          slip_count <= slip_count - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      slip_count <= 9;
    end if;
  end process;

  mark_o <= '1' when slip_count = 0 else '0';
  
  master: iserdese2
    generic map (
      data_rate => "DDR",
      data_width => 10,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => iobdelay_c,
      serdes_mode => "MASTER"
      )
    port map (
      q1 => d(0),
      q2 => d(1),
      q3 => d(2),
      q4 => d(3),
      q5 => d(4),
      q6 => d(5),
      q7 => d(6),
      q8 => d(7),
      shiftout1 => cascade1,
      shiftout2 => cascade2,
      bitslip => bitslip_i,
      ce1 => '1',
      ce2 => '1',
      clk => bit_clock_i,
      clkb => bit_clock_n_s,
      clkdiv => word_clock_i,
      clkdivp => '0',
      d => d_i,
      ddly => ddly_i,
      rst => reset_s,
      shiftin1 => '0',
      shiftin2 => '0',
      dynclkdivsel => '0',
      dynclksel => '0',
      ofb => '0',
      oclk => '0',
      oclkb => '0'
      );

  slave: iserdese2
    generic map (
      data_rate => "DDR",
      data_width => 10,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => iobdelay_c,
      serdes_mode => "SLAVE"
      )
    port map (
      q3 => d(8),
      q4 => d(9),
      shiftin1 => cascade1,
      shiftin2 => cascade2,
      bitslip => bitslip_i,
      ce1 => '1',
      ce2 => '1',
      clk => bit_clock_i,
      clkb => bit_clock_n_s,
      clkdiv => word_clock_i,
      clkdivp => '0',
      d => '0',
      ddly => '0',
      rst => reset_s,
      dynclkdivsel => '0',
      dynclksel => '0',
      ofb => '0',
      oclk => '0',
      oclkb => '0'
      );

end architecture;
