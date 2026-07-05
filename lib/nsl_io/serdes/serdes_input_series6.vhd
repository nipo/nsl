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

architecture series6 of serdes_input is

  attribute BOX_TYPE : string;

  component ISERDES2
    generic (
      BITSLIP_ENABLE : boolean := FALSE;
      DATA_RATE : string := "SDR";
      DATA_WIDTH : integer := 1;
      INTERFACE_TYPE : string := "NETWORKING";
      SERDES_MODE : string := "NONE"
      );
    port (
      CFB0 : out std_ulogic;
      CFB1 : out std_ulogic;
      DFB : out std_ulogic;
      FABRICOUT : out std_ulogic;
      INCDEC : out std_ulogic;
      Q1 : out std_ulogic;
      Q2 : out std_ulogic;
      Q3 : out std_ulogic;
      Q4 : out std_ulogic;
      SHIFTOUT : out std_ulogic;
      VALID : out std_ulogic;
      BITSLIP : in std_ulogic := 'L';
      CE0 : in std_ulogic := 'H';
      CLK0 : in std_ulogic;
      CLK1 : in std_ulogic;
      CLKDIV : in std_ulogic;
      D : in std_ulogic;
      IOCE : in std_ulogic := 'H';
      RST : in std_ulogic := 'L';
      SHIFTIN : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    ISERDES2 : component is "PRIMITIVE";

  constant iobdelay_c: string := nsl_data.text.if_else(from_delay_c, "BOTH", "NONE");
  constant data_rate_c: string := nsl_data.text.if_else(ddr_mode_c, "DDR", "SDR");
  constant cascade_needed_c: boolean := ratio_c > 4;
  constant master_mode_c: string := nsl_data.text.if_else(cascade_needed_c, "MASTER", "NONE");
  signal bitslip_s, cascade_s, reset_s, serial_clock_n_s : std_ulogic;
  -- First RX at high order.
  signal parallel_s: std_ulogic_vector(0 to 7) := (others => '-');
  signal slip_count_s: integer range 0 to ratio_c-1;

begin

  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;
  assert (not ddr_mode_c) or ((ratio_c mod 2) = 0)
    report "DDR can only support even ratios"
    severity failure;

  assert ((ratio_c >= 2) and (ratio_c <= 8))
    report "Only support ratio in range 2:8"
    severity failure;

  reset_s <= not reset_n_i;

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
  
  master: iserdes2
    generic map (
      data_rate => data_rate_c,
      data_width => ratio_c,
      interface_type => "NETWORKING",
      serdes_mode => master_mode_c,
      bitslip_enable => true
      )
    port map (
      q1 => parallel_s(3),
      q2 => parallel_s(2),
      q3 => parallel_s(1),
      q4 => parallel_s(0),
      shiftout => cascade_s,
      bitslip => bitslip_s,
      ce0 => '1',
      clk0 => serial_clock_i,
      clk1 => serial_clock_n_s,
      clkdiv => parallel_clock_i,
      d => serial_i,
      ioce => '1',
      rst => reset_s,
      shiftin => '0'
      );

  has_slave: if cascade_needed_c
  generate
    slave: iserdes2
      generic map (
        data_rate => data_rate_c,
        data_width => ratio_c,
        interface_type => "NETWORKING",
        serdes_mode => "SLAVE",
        bitslip_enable => true
        )
      port map (
        q1 => parallel_s(7),
        q2 => parallel_s(6),
        q3 => parallel_s(5),
        q4 => parallel_s(4),
        shiftin => cascade_s,
        bitslip => bitslip_s,
        ce0 => '1',
        clk0 => serial_clock_i,
        clk1 => serial_clock_n_s,
        clkdiv => parallel_clock_i,
        d => '0',
        ioce => '1',
        rst => reset_s
        );
  end generate;

end architecture;
