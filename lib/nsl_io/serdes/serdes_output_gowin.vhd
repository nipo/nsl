library ieee;
use ieee.std_logic_1164.all;

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

architecture gowin of serdes_output is

  signal d_s: std_ulogic_vector(0 to ratio_c-1);
  signal reset_s: std_ulogic;

  attribute syn_black_box: boolean ;

begin

  assert ddr_mode_c
    report "Only supports DDR mode"
    severity failure;

  assert ratio_c = 4 or ratio_c = 8 or ratio_c = 10 or ratio_c = 16
    report "Only supports ratio of 4, 8, 10, 16"
    severity failure;

  reset_s <= not reset_n_i;
  
  ltr: if left_first_c
  generate
    d_s <= parallel_i;
  end generate;

  rtl: if not left_first_c
  generate
    in_map: for i in 0 to ratio_c-1
    generate
      d_s(ratio_c-1-i) <= parallel_i(i);
    end generate;
  end generate;

  p4: if ratio_c = 4
  generate
    component OSER4 is
      port (
        D0 : in std_logic;
        D1 : in std_logic;
        D2 : in std_logic;
        D3 : in std_logic;
        FCLK : in std_logic;
        PCLK : in std_logic;
        Q0 : out std_logic;
        Q1 : out std_logic;
        RESET : in std_logic;
        TX0 : in std_logic;
        TX1 : in std_logic
        );
    end component;
    attribute syn_black_box of OSER4 : component is true;
  begin
    inst: OSER4
      port map(
        q0 => serial_o,
        d0 => d_s(0),
        d1 => d_s(1),
        d2 => d_s(2),
        d3 => d_s(3),
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        reset => reset_s,
        tx0 => '0',
        tx1 => '0'
        );
  end generate;

  p8: if ratio_c = 8
  generate
    component OSER8 is
      port (
        D0 : in std_logic;
        D1 : in std_logic;
        D2 : in std_logic;
        D3 : in std_logic;
        D4 : in std_logic;
        D5 : in std_logic;
        D6 : in std_logic;
        D7 : in std_logic;
        FCLK : in std_logic;
        PCLK : in std_logic;
        Q0 : out std_logic;
        Q1 : out std_logic;
        RESET : in std_logic;
        TX0 : in std_logic;
        TX1 : in std_logic;
        TX2 : in std_logic;
        TX3 : in std_logic
        );
    end component;
    attribute syn_black_box of OSER8 : component is true;
  begin
    inst: OSER8
      port map(
        q0 => serial_o,
        d0 => d_s(0),
        d1 => d_s(1),
        d2 => d_s(2),
        d3 => d_s(3),
        d4 => d_s(4),
        d5 => d_s(5),
        d6 => d_s(6),
        d7 => d_s(7),
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        reset => reset_s,
        tx0 => '0',
        tx1 => '0',
        tx2 => '0',
        tx3 => '0'
        );
  end generate;

  p10: if ratio_c = 10
  generate
    component OSER10 is
      port (
        D0 : in std_logic;
        D1 : in std_logic;
        D2 : in std_logic;
        D3 : in std_logic;
        D4 : in std_logic;
        D5 : in std_logic;
        D6 : in std_logic;
        D7 : in std_logic;
        D8 : in std_logic;
        D9 : in std_logic;
        FCLK : in std_logic;
        PCLK : in std_logic;
        Q : out std_logic;
        RESET : in std_logic
        );
    end component;
    attribute syn_black_box of OSER10 : component is true;
  begin
    inst: OSER10
      port map(
        q => serial_o,
        d0 => d_s(0),
        d1 => d_s(1),
        d2 => d_s(2),
        d3 => d_s(3),
        d4 => d_s(4),
        d5 => d_s(5),
        d6 => d_s(6),
        d7 => d_s(7),
        d8 => d_s(8),
        d9 => d_s(9),
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        reset => reset_s
        );
  end generate;

  p16: if ratio_c = 16
  generate
    component OSER16 is
      PORT (
        D0 : in std_logic;
        D1 : in std_logic;
        D2 : in std_logic;
        D3 : in std_logic;
        D4 : in std_logic;
        D5 : in std_logic;
        D6 : in std_logic;
        D7 : in std_logic;
        D8 : in std_logic;
        D9 : in std_logic;
        D10 : in std_logic;
        D11 : in std_logic;
        D12 : in std_logic;
        D13 : in std_logic;
        D14 : in std_logic;
        D15 : in std_logic;
        PCLK : in std_logic;
        RESET : in std_logic;
        FCLK : in std_logic;
        Q : OUT std_logic
        );
    end component;
    attribute syn_black_box of OSER16 : component is true;
  begin
    inst: OSER16
      port map(
        q => serial_o,
        d0 => d_s(0),
        d1 => d_s(1),
        d2 => d_s(2),
        d3 => d_s(3),
        d4 => d_s(4),
        d5 => d_s(5),
        d6 => d_s(6),
        d7 => d_s(7),
        d8 => d_s(8),
        d9 => d_s(9),
        d10 => d_s(10),
        d11 => d_s(11),
        d12 => d_s(12),
        d13 => d_s(13),
        d14 => d_s(14),
        d15 => d_s(15),
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        reset => reset_s
        );
  end generate;
    
end architecture;
