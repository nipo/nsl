library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

architecture gowin of serdes_input is

  signal reset_s, serial_clock_n_s : std_ulogic;
  signal d_s: std_ulogic_vector(0 to ratio_c-1);
  signal slip_count_s: integer range 0 to ratio_c-1;

  attribute syn_black_box: boolean ;

begin

  assert ddr_mode_c
    report "Only supports DDR mode"
    severity failure;

  assert ratio_c = 4 or ratio_c = 8 or ratio_c = 10 or ratio_c = 16
    report "Only supports ratio of 4, 8, 10, 16"
    severity failure;

  reset_s <= not reset_n_i;

  slip_tracker: process(parallel_clock_i, reset_n_i) is
  begin
    if rising_edge(parallel_clock_i) then
      if bitslip_i = '1' then
        if slip_count_s = 0 then
          slip_count_s <= ratio_c-1;
        else
          slip_count_s <= slip_count_s - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      slip_count_s <= 0;
    end if;
  end process;

  mark_o <= '1' when slip_count_s = 0 else '0';

  ltr: if left_first_c
  generate
    parallel_o <= d_s;
  end generate;

  rtl: if not left_first_c
  generate
    in_map: for i in 0 to ratio_c-1
    generate
      parallel_o(ratio_c-1-i) <= d_s(i);
    end generate;
  end generate;

  serial_clock_n_s <= not serial_clock_i;

  p4: if ratio_c = 4
  generate
    component IDES4 is
      PORT (
        D : IN std_logic;
        RESET : IN std_logic;
        CALIB : IN std_logic;
        FCLK : IN std_logic;
        PCLK : IN std_logic;
        Q0 : OUT std_logic;
        Q1 : OUT std_logic;
        Q2 : OUT std_logic;
        Q3 : OUT std_logic
        );
    end component;
    attribute syn_black_box of IDES4 : component is true;
  begin
    inst: IDES4
      port map (
        q0 => d_s(0),
        q1 => d_s(1),
        q2 => d_s(2),
        q3 => d_s(3),
        d => serial_i,
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        calib => bitslip_i,
        reset => reset_s
        );
  end generate;

  p8: if ratio_c = 8
  generate
    component IDES8 is
      PORT (
        D,RESET : IN std_logic;
        CALIB : IN std_logic;
        FCLK,PCLK : IN std_logic;
        Q0 : OUT std_logic;
        Q1 : OUT std_logic;
        Q2 : OUT std_logic;
        Q3 : OUT std_logic;
        Q4 : OUT std_logic;
        Q5 : OUT std_logic;
        Q6 : OUT std_logic;
        Q7 : OUT std_logic
        );
    end component;
    attribute syn_black_box of IDES8 : component is true;
  begin
    inst: IDES8
      port map (
        q0 => d_s(0),
        q1 => d_s(1),
        q2 => d_s(2),
        q3 => d_s(3),
        q4 => d_s(4),
        q5 => d_s(5),
        q6 => d_s(6),
        q7 => d_s(7),
        d => serial_i,
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        calib => bitslip_i,
        reset => reset_s
        );
  end generate;

  p10: if ratio_c = 10
  generate
    component IDES10 is
      PORT (
        D,RESET : IN std_logic;
        CALIB : IN std_logic;
        FCLK,PCLK : IN std_logic;
        Q0 : OUT std_logic;
        Q1 : OUT std_logic;
        Q2 : OUT std_logic;
        Q3 : OUT std_logic;
        Q4 : OUT std_logic;
        Q5 : OUT std_logic;
        Q6 : OUT std_logic;
        Q7 : OUT std_logic;
        Q8 : OUT std_logic;
        Q9 : OUT std_logic
        );
    end component;
    attribute syn_black_box of IDES10 : component is true;
  begin
    inst: IDES10
      port map (
        q0 => d_s(0),
        q1 => d_s(1),
        q2 => d_s(2),
        q3 => d_s(3),
        q4 => d_s(4),
        q5 => d_s(5),
        q6 => d_s(6),
        q7 => d_s(7),
        q8 => d_s(8),
        q9 => d_s(9),
        d => serial_i,
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        calib => bitslip_i,
        reset => reset_s
        );
  end generate;

  p16: if ratio_c = 16
  generate
    component IDES16 is
      PORT (
        D,RESET : IN std_logic;
        CALIB : IN std_logic;
        FCLK,PCLK : IN std_logic;
        Q0 : OUT std_logic;
        Q1 : OUT std_logic;
        Q2 : OUT std_logic;
        Q3 : OUT std_logic;
        Q4 : OUT std_logic;
        Q5 : OUT std_logic;
        Q6 : OUT std_logic;
        Q7 : OUT std_logic;
        Q8 : OUT std_logic;
        Q9 : OUT std_logic;
        Q10 : OUT std_logic;
        Q11 : OUT std_logic;
        Q12 : OUT std_logic;
        Q13 : OUT std_logic;
        Q14 : OUT std_logic;
        Q15 : OUT std_logic
        );
    end component;
    attribute syn_black_box of IDES16 : component is true;
  begin
    inst: IDES16
      port map (
        q0 => d_s(0),
        q1 => d_s(1),
        q2 => d_s(2),
        q3 => d_s(3),
        q4 => d_s(4),
        q5 => d_s(5),
        q6 => d_s(6),
        q7 => d_s(7),
        q8 => d_s(8),
        q9 => d_s(9),
        q10 => d_s(9),
        q11 => d_s(10),
        q12 => d_s(12),
        q13 => d_s(13),
        q14 => d_s(14),
        q15 => d_s(15),
        d => serial_i,
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        calib => bitslip_i,
        reset => reset_s
        );
  end generate;

end architecture;
