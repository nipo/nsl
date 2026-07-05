library ieee;
use ieee.std_logic_1164.all;

library nsl_data;

entity serdes_input is
  generic(
    left_first_c : boolean := false;
    ddr_mode_c : boolean := false;
    from_delay_c : boolean := false;
    ratio_c : positive
    );
  port(
    serial_clock_i : in std_ulogic;
    parallel_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    serial_i : in std_ulogic;
    parallel_o : out std_ulogic_vector(0 to ratio_c-1);

    bitslip_i : in std_ulogic;
    mark_o : out std_ulogic
    );
end entity;

architecture series7 of serdes_input is

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

  constant iobdelay_c: string := nsl_data.text.if_else(from_delay_c, "BOTH", "NONE");
  constant data_rate_c: string := nsl_data.text.if_else(ddr_mode_c, "DDR", "SDR");
  constant cascade_needed_c: boolean := ratio_c > 8;
  signal bitslip_s, cascade1_s, cascade2_s, reset_s, serial_clock_n_s : std_ulogic;
  -- First RX at high order.
  signal parallel_s: std_ulogic_vector(0 to 13) := (others => '-');
  signal slip_count_s: integer range 0 to ratio_c-1;
  signal d_i, ddly_i: std_ulogic;

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
  
  output: process(parallel_s) is
  begin
    for i in 0 to ratio_c-1
    loop
      if left_first_c then
        parallel_o(i) <= parallel_s(ratio_c-1-i);
      else
        parallel_o(i) <= parallel_s(i);
      end if;
    end loop;
  end process;

  serial_clock_n_s <= not serial_clock_i;

  slip_tracker: process(parallel_clock_i, reset_n_i) is
  begin
    if rising_edge(parallel_clock_i) then
      bitslip_s <= '0';
      if bitslip_i = '1' and bitslip_s = '0' then
        bitslip_s <= '1';
        if slip_count_s = 0 then
          slip_count_s <= ratio_c-1;
        else
          slip_count_s <= slip_count_s - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      slip_count_s <= 0;
      bitslip_s <= '0';
    end if;
  end process;

  mark_o <= '1' when slip_count_s = 0 else '0';
  
  master: iserdese2
    generic map (
      data_rate => data_rate_c,
      data_width => ratio_c,
      interface_type => "NETWORKING",
      dyn_clkdiv_inv_en => "FALSE",
      dyn_clk_inv_en => "FALSE",
      num_ce => 2,
      ofb_used => "FALSE",
      iobdelay => iobdelay_c,
      serdes_mode => "MASTER"
      )
    port map (
      q1 => parallel_s(0),
      q2 => parallel_s(1),
      q3 => parallel_s(2),
      q4 => parallel_s(3),
      q5 => parallel_s(4),
      q6 => parallel_s(5),
      q7 => parallel_s(6),
      q8 => parallel_s(7),
      shiftout1 => cascade1_s,
      shiftout2 => cascade2_s,
      bitslip => bitslip_s,
      ce1 => '1',
      ce2 => '1',
      clk => serial_clock_i,
      clkb => serial_clock_n_s,
      clkdiv => parallel_clock_i,
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

  has_slave: if cascade_needed_c
  generate
    slave: iserdese2
      generic map (
        data_rate => data_rate_c,
        data_width => ratio_c,
        interface_type => "NETWORKING",
        dyn_clkdiv_inv_en => "FALSE",
        dyn_clk_inv_en => "FALSE",
        num_ce => 2,
        ofb_used => "FALSE",
        iobdelay => iobdelay_c,
        serdes_mode => "SLAVE"
        )
      port map (
        q3 => parallel_s(8),
        q4 => parallel_s(9),
        q5 => parallel_s(10),
        q6 => parallel_s(11),
        q7 => parallel_s(12),
        q8 => parallel_s(13),
        shiftin1 => cascade1_s,
        shiftin2 => cascade2_s,
        bitslip => bitslip_s,
        ce1 => '1',
        ce2 => '1',
        clk => serial_clock_i,
        clkb => serial_clock_n_s,
        clkdiv => parallel_clock_i,
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
  end generate;

end architecture;
