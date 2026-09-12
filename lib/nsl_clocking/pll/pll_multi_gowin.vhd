library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_hwconfig, nsl_synthesis, work;
use nsl_data.text.all;
use nsl_hwconfig.gowin_config.all;
use work.pll.all;

entity pll_multi is
  generic(
    config_c : pll_config_t
    );
  port(
    clock_i : in std_ulogic;
    clock_o : out std_ulogic_vector(0 to config_c.output_count-1);

    reset_n_i : in std_ulogic;
    locked_o : out std_ulogic
    );
end entity;

architecture gowin of pll_multi is

  attribute syn_black_box: boolean;

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);

  -- Realization parameters of the output carried by one physical
  -- port.  Unused ports get a safe divisor and stay disabled.
  function port_mapping(p: natural) return pll_output_mapping_t
  is
  begin
    for i in 0 to mapping_c.output_count - 1 loop
      if mapping_c.output(i).enabled
        and mapping_c.output(i).port_index = p then
        return mapping_c.output(i);
      end if;
    end loop;
    return (enabled => false,
            port_index => 0,
            divisor => (num => 8, den => 1),
            hz => 0,
            exact => false,
            phase => pll_ratio_zero_c);
  end function;

  function odiv_int(p: natural) return integer
  is
    constant m: pll_output_mapping_t := port_mapping(p);
  begin
    return m.divisor.num / m.divisor.den;
  end function;

  function odiv_frac8(p: natural) return integer
  is
    constant m: pll_output_mapping_t := port_mapping(p);
  begin
    return ((m.divisor.num mod m.divisor.den) * 8) / m.divisor.den;
  end function;

  -- Phase shift of the output carried by port p, in eighths of a VCO
  -- cycle.  A phase is stated as a fraction of the output cycle, and
  -- an output cycle is `divisor` VCO cycles, so the eighths come out
  -- as phase * 8 * divisor -- a whole number, the solver having
  -- refused anything off that grid.
  function pe_eighths(p: natural) return integer
  is
    constant m: pll_output_mapping_t := port_mapping(p);
  begin
    if m.phase.num = 0 then
      return 0;
    end if;
    return (m.phase.num * 8 * (m.divisor.num / m.divisor.den)) / m.phase.den;
  end function;

  -- Whole VCO cycles of the shift, which is what CLKOUTx_PE_COARSE
  -- takes...
  function pe_coarse(p: natural) return integer
  is
  begin
    return pe_eighths(p) / 8;
  end function;

  -- ... and the eighths left over, which CLKOUTx_PE_FINE takes.
  function pe_fine(p: natural) return integer
  is
  begin
    return pe_eighths(p) mod 8;
  end function;

  function en_str(p: natural) return string
  is
  begin
    if port_mapping(p).enabled then
      return "TRUE";
    end if;
    return "FALSE";
  end function;

  constant fin_hz_str : string := to_string(config_c.input_hz);
  constant fin_hz_str2 : string(fin_hz_str'length downto 1) := fin_hz_str;
  constant fin_mhz_str : string := fin_hz_str2(fin_hz_str2'left downto 7) & "." & fin_hz_str2(6 downto 1);

  signal reset_s : std_ulogic;
  signal clkout_s : std_ulogic_vector(0 to 6);

begin



  log0: nsl_synthesis.logging.synth_log
    generic map(
      message_c => "Gowin PLL: " & to_string(mapping_c)
      )
    port map(
      unused_i => '0'
      );

  reset_s <= not reset_n_i;

  outputs: for i in 0 to config_c.output_count - 1 generate
    constant period_str_c : string := to_string(1.0e9 / mapping_output_hz(mapping_c, i));
    constant buffered_c : boolean
      := config_c.output(i).routing /= work.pll_backend.pll_routing_id("NONE");
    signal buffered_s : std_ulogic;
    attribute period: string;
    attribute period of buffered_s : signal is period_str_c & " ns";
  begin
    buffered: if buffered_c generate
      buf: work.distribution.clock_buffer
        port map(
          clock_i => clkout_s(mapping_c.output(i).port_index),
          clock_o => buffered_s
          );
    end generate;

    -- Straight out of the block: the global network would not carry
    -- this rate, and whatever takes it has its own input stage.
    raw: if not buffered_c generate
      buffered_s <= clkout_s(mapping_c.output(i).port_index);
    end generate;

    clock_o(i) <= buffered_s;
  end generate;

  use_rpll: if pll_type = "rpll"
  generate
    component rpll is
      generic(
        fclkin : string := "100.0";
        device : string := "gw1n-2";
        dyn_idiv_sel : string := "false";
        idiv_sel : integer := 0;
        dyn_fbdiv_sel : string := "false";
        fbdiv_sel : integer := 0;
        dyn_odiv_sel : string := "false";
        odiv_sel : integer := 8;
        psda_sel : string := "0000";
        dyn_da_en : string := "false";
        dutyda_sel : string := "1000";
        clkout_ft_dir : bit := '1';
        clkoutp_ft_dir : bit := '1';
        clkout_dly_step : integer := 0;
        clkoutp_dly_step : integer := 0;

        clkoutd3_src : string := "clkout";
        clkfb_sel : string := "internal";
        clkout_bypass : string := "false";
        clkoutp_bypass : string := "false";
        clkoutd_bypass : string := "false";
        clkoutd_src : string := "clkout";
        dyn_sdiv_sel : integer := 2
        );
      port(
        clkin : in std_logic;
        clkfb : in std_logic:='0';
        idsel : in std_logic_vector(5 downto 0);
        fbdsel : in std_logic_vector(5 downto 0);
        odsel : in std_logic_vector(5 downto 0);
        reset : in std_logic:='0';
        reset_p : in std_logic:='0';
        psda,fdly : in std_logic_vector(3 downto 0);
        dutyda : in std_logic_vector(3 downto 0);
        lock : out std_logic;
        clkout : out std_logic;
        clkoutd : out std_logic;
        clkoutp : out std_logic;
        clkoutd3 : out std_logic
        );
    end component rpll;
    attribute syn_black_box of rpll : component is true;
  begin
    inst: rpll
      generic map(
        fclkin => fin_mhz_str,
        device => nsl_hwconfig.gowin_config.device_name,
        idiv_sel => mapping_c.refdiv - 1,
        fbdiv_sel => mapping_c.fbdiv.num - 1,
        odiv_sel => odiv_int(0),
        clkfb_sel => "internal",
        clkoutd_src => "CLKOUT",
        dyn_idiv_sel => "false",
        dyn_fbdiv_sel => "false",
        dyn_odiv_sel => "false"
        )
      port map(
        clkin => clock_i,
        idsel => "000000",
        fbdsel => "000000",
        odsel => "000000",
        reset => reset_s,
        reset_p => '0',
        psda => "0000",
        fdly => "0000",
        dutyda => "0000",
        lock => locked_o,
        clkout => clkout_s(0)
        );
  end generate;

  use_pll: if pll_type = "pll"
  generate
    component pll is
      generic(
        fclkin : string := "100.0";
        device : string := "GW2A-18";
        dyn_idiv_sel : string := "false";
        idiv_sel : integer := 0;
        dyn_fbdiv_sel : string := "false";
        fbdiv_sel : integer := 0;
        dyn_odiv_sel : string := "false";
        odiv_sel : integer := 8;
        psda_sel : string := "0000";
        dyn_da_en : string := "false";
        dutyda_sel : string := "1000";
        clkout_ft_dir : bit := '1';
        clkoutp_ft_dir : bit := '1';
        clkout_dly_step : integer := 0;
        clkoutp_dly_step : integer := 0;

        clkoutd3_src : string := "CLKOUT";
        clkfb_sel : string := "internal";
        clkout_bypass : string := "false";
        clkoutp_bypass : string := "false";
        clkoutd_bypass : string := "false";
        clkoutd_src : string := "CLKOUT";
        dyn_sdiv_sel : integer := 2
        );
      port(
        clkin : in std_logic;
        clkfb : in std_logic:='0';
        idsel : in std_logic_vector(5 downto 0);
        fbdsel : in std_logic_vector(5 downto 0);
        odsel : in std_logic_vector(5 downto 0);
        reset : in std_logic:='0';
        reset_p : in std_logic:='0';
        reset_i : in std_logic:='0';
        reset_s : in std_logic:='0';
        psda,fdly : in std_logic_vector(3 downto 0);
        dutyda : in std_logic_vector(3 downto 0);
        lock : out std_logic;
        clkout : out std_logic;
        clkoutd : out std_logic;
        clkoutp : out std_logic;
        clkoutd3 : out std_logic
        );
    end component pll;
    attribute syn_black_box of pll : component is true;
  begin
    inst: pll
      generic map(
        fclkin => fin_mhz_str,
        device => nsl_hwconfig.gowin_config.device_name,
        idiv_sel => mapping_c.refdiv - 1,
        fbdiv_sel => mapping_c.fbdiv.num - 1,
        odiv_sel => odiv_int(0),
        clkfb_sel => "internal",
        clkoutd_src => "CLKOUT",
        dyn_idiv_sel => "false",
        dyn_fbdiv_sel => "false",
        dyn_odiv_sel => "false"
        )
      port map(
        clkin => clock_i,
        idsel => "000000",
        fbdsel => "000000",
        odsel => "000000",
        reset => reset_s,
        reset_p => '0',
        psda => "0000",
        fdly => "0000",
        dutyda => "0000",
        lock => locked_o,
        clkout => clkout_s(0)
        );
  end generate;

  use_plla: if pll_type = "plla"
  generate
    component plla is
      generic(
        fclkin : string := "100.0";
        idiv_sel : integer := 1;
        fbdiv_sel : integer := 1;

        odiv0_sel : integer := 8;
        odiv1_sel : integer := 8;
        odiv2_sel : integer := 8;
        odiv3_sel : integer := 8;
        odiv4_sel : integer := 8;
        odiv5_sel : integer := 8;
        odiv6_sel : integer := 8;
        mdiv_sel : integer := 8;
        mdiv_frac_sel : integer := 0;
        odiv0_frac_sel : integer := 0;

        clkout0_en : string := "TRUE";
        clkout1_en : string := "FALSE";
        clkout2_en : string := "FALSE";
        clkout3_en : string := "FALSE";
        clkout4_en : string := "FALSE";
        clkout5_en : string := "FALSE";
        clkout6_en : string := "FALSE";

        clkfb_sel : string := "INTERNAL";

        clkout0_dt_dir : bit := '1';
        clkout1_dt_dir : bit := '1';
        clkout2_dt_dir : bit := '1';
        clkout3_dt_dir : bit := '1';
        clkout0_dt_step : integer := 0;
        clkout1_dt_step : integer := 0;
        clkout2_dt_step : integer := 0;
        clkout3_dt_step : integer := 0;

        clk0_in_sel : bit := '0';
        clk0_out_sel : bit := '0';
        clk1_in_sel : bit := '0';
        clk1_out_sel : bit := '0';
        clk2_in_sel : bit := '0';
        clk2_out_sel : bit := '0';
        clk3_in_sel : bit := '0';
        clk3_out_sel : bit := '0';
        clk4_in_sel : bit_vector := "00";
        clk4_out_sel : bit := '0';
        clk5_in_sel : bit := '0';
        clk5_out_sel : bit := '0';
        clk6_in_sel : bit := '0';
        clk6_out_sel : bit := '0';

        dyn_dpa_en : string := "FALSE";

        clkout0_pe_coarse : integer := 0;
        clkout0_pe_fine : integer := 0;
        clkout1_pe_coarse : integer := 0;
        clkout1_pe_fine : integer := 0;
        clkout2_pe_coarse : integer := 0;
        clkout2_pe_fine : integer := 0;
        clkout3_pe_coarse : integer := 0;
        clkout3_pe_fine : integer := 0;
        clkout4_pe_coarse : integer := 0;
        clkout4_pe_fine : integer := 0;
        clkout5_pe_coarse : integer := 0;
        clkout5_pe_fine : integer := 0;
        clkout6_pe_coarse : integer := 0;
        clkout6_pe_fine : integer := 0;

        dyn_pe0_sel : string := "FALSE";
        dyn_pe1_sel : string := "FALSE";
        dyn_pe2_sel : string := "FALSE";
        dyn_pe3_sel : string := "FALSE";
        dyn_pe4_sel : string := "FALSE";
        dyn_pe5_sel : string := "FALSE";
        dyn_pe6_sel : string := "FALSE";

        de0_en : string := "FALSE";
        de1_en : string := "FALSE";
        de2_en : string := "FALSE";
        de3_en : string := "FALSE";
        de4_en : string := "FALSE";
        de5_en : string := "FALSE";
        de6_en : string := "FALSE";

        reset_i_en : string := "FALSE";
        reset_o_en : string := "FALSE";

        icp_sel : std_logic_vector(5 downto 0) := "XXXXXX";
        lpf_res : std_logic_vector(2 downto 0) := "XXX";
        lpf_cap : bit_vector := "00";

        ssc_en : string := "FALSE";

        vr_en : bit := '0'
        );
      port(
        clkin : in std_logic;
        clkfb : in std_logic:='0';
        reset,pllpwd : in std_logic:='0';
        reset_i,reset_o : in std_logic:='0';
        pssel : in std_logic_vector(2 downto 0);
        psdir,pspulse : in std_logic;
        sscpol,sscon : in std_logic;
        sscmdsel : in std_logic_vector(6 downto 0);
        sscmdsel_frac : in std_logic_vector(2 downto 0);
        mdclk : in std_logic;
        mdopc : in std_logic_vector(1 downto 0);
        mdainc : in std_logic;
        mdwdi : in std_logic_vector(7 downto 0);

        mdrdo : out std_logic_vector(7 downto 0);
        lock : out std_logic;
        clkout0,clkout1 : out std_logic;
        clkout2,clkout3 : out std_logic;
        clkout4,clkout5 : out std_logic;
        clkout6,clkfbout : out std_logic
        );
    end component plla;
    attribute syn_black_box of plla : component is true;
  begin
    inst: plla
      generic map(
        fclkin => fin_mhz_str,
        idiv_sel => mapping_c.refdiv,
        fbdiv_sel => 1,
        mdiv_sel => mapping_c.fbdiv.num,
        mdiv_frac_sel => 0,
        odiv0_sel => odiv_int(0),
        odiv1_sel => odiv_int(1),
        odiv2_sel => odiv_int(2),
        odiv3_sel => odiv_int(3),
        odiv4_sel => odiv_int(4),
        odiv5_sel => odiv_int(5),
        odiv6_sel => odiv_int(6),
        odiv0_frac_sel => odiv_frac8(0),
        clkout0_pe_coarse => pe_coarse(0),
        clkout0_pe_fine => pe_fine(0),
        clkout1_pe_coarse => pe_coarse(1),
        clkout1_pe_fine => pe_fine(1),
        clkout2_pe_coarse => pe_coarse(2),
        clkout2_pe_fine => pe_fine(2),
        clkout3_pe_coarse => pe_coarse(3),
        clkout3_pe_fine => pe_fine(3),
        clkout4_pe_coarse => pe_coarse(4),
        clkout4_pe_fine => pe_fine(4),
        clkout5_pe_coarse => pe_coarse(5),
        clkout5_pe_fine => pe_fine(5),
        clkout6_pe_coarse => pe_coarse(6),
        clkout6_pe_fine => pe_fine(6),
        clkout0_en => en_str(0),
        clkout1_en => en_str(1),
        clkout2_en => en_str(2),
        clkout3_en => en_str(3),
        clkout4_en => en_str(4),
        clkout5_en => en_str(5),
        clkout6_en => en_str(6),
        clkfb_sel => "INTERNAL"
        )
      port map(
        clkin => clock_i,
        reset => reset_s,
        pssel => "000",
        psdir => '0',
        pspulse => '0',
        sscpol => '0',
        sscon => '0',
        sscmdsel => "0000000",
        sscmdsel_frac => "000",
        mdclk => '0',
        mdopc => "00",
        mdainc => '0',
        mdwdi => x"00",
        lock => locked_o,
        clkout0 => clkout_s(0),
        clkout1 => clkout_s(1),
        clkout2 => clkout_s(2),
        clkout3 => clkout_s(3),
        clkout4 => clkout_s(4),
        clkout5 => clkout_s(5),
        clkout6 => clkout_s(6)
        );
  end generate;

end architecture gowin;
