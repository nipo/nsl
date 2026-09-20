library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

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

architecture gowin of serdes_output_tristated is

  signal d_s: std_ulogic_vector(0 to ratio_c-1);
  -- The serialiser wants the complement of an output enable: its
  -- tristate output reaches a pad driver whose own enable is active
  -- low, so a set bit means let go.
  signal tx_s: std_ulogic_vector(0 to ratio_c/2-1);
  signal disable_s: std_logic;
  signal reset_s: std_ulogic;

  attribute syn_black_box: boolean;

begin

  assert ddr_mode_c
    report "Only supports DDR mode"
    severity failure;

  assert ratio_c = 4 or ratio_c = 8
    report "Only the 4 and 8 wide serialisers carry a tristate path"
    severity failure;

  reset_s <= not reset_n_i;

  ltr: if left_first_c
  generate
    d_s <= parallel_i;
    tx_s <= not output_enable_i;
  end generate;

  rtl: if not left_first_c
  generate
    in_map: for i in 0 to ratio_c-1
    generate
      d_s(ratio_c-1-i) <= parallel_i(i);
    end generate;

    en_map: for i in 0 to ratio_c/2-1
    generate
      tx_s(ratio_c/2-1-i) <= not output_enable_i(i);
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
        q0 => pad_o.v,
        q1 => disable_s,
        d0 => d_s(0),
        d1 => d_s(1),
        d2 => d_s(2),
        d3 => d_s(3),
        fclk => serial_clock_i,
        pclk => parallel_clock_i,
        reset => reset_s,
        tx0 => tx_s(0),
        tx1 => tx_s(1)
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
        q0 => pad_o.v,
        q1 => disable_s,
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
        tx0 => tx_s(0),
        tx1 => tx_s(1),
        tx2 => tx_s(2),
        tx3 => tx_s(3)
        );
  end generate;

  pad_o.en <= not disable_s;

end architecture;
