library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_logic;
use work.tmds.all;
use nsl_logic.logic.all;

entity tmds_encoder is
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    de_i : in std_ulogic;
    pixel_i : in  unsigned(7 downto 0);

    terc4_i : in std_ulogic := '0';
    control_i : in std_ulogic_vector(3 downto 0) := "0000";

    symbol_o : out tmds_symbol_t
    );
end tmds_encoder;

architecture beh of tmds_encoder is

  type regs_t is
  record
    -- Count DC bias divided by 2
    dc_bias : signed(4 downto 0);

    qm : std_ulogic_vector(7 downto 0);
    qm8 : std_ulogic;
    qm_disp : signed(3 downto 0);
    de, terc4: boolean;

    dout : tmds_symbol_t;
  end record;

  signal r, rin: regs_t;

  procedure pixel_word_encode(pixel: in unsigned(7 downto 0);
                              qm: out std_ulogic_vector(7 downto 0);
                              qm8: out std_ulogic;
                              qm_disp: out signed(3 downto 0)
                              )
  is
    variable ones : integer range 0 to 8;
    variable dw : std_ulogic_vector(7 downto 0);
  begin
    dw(0) := pixel(0);
    for i in 1 to 7
    loop
      dw(i) := dw(i-1) xor pixel(i);
    end loop;

    ones := popcnt(std_ulogic_vector(pixel));
    if ones > 4 or (ones = 4 and pixel(0) = '0') then
      dw := dw xor "10101010";
      qm8 := '0';
    else
      qm8 := '1';
    end if;

    qm := dw;
    -- (count(ones) - count(zeros)) / 2 == count(ones) - 4
    qm_disp := to_signed(popcnt(dw) - 4, 4);
  end procedure;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.dc_bias <= (others => '0');
      r.qm <= (others => '0');
      r.qm8 <= '0';
      r.de <= false;
      r.terc4 <= false;
      r.dout <= (others => '0');
    end if;
  end process;
  
  transition: process(r, de_i, pixel_i, terc4_i, control_i) is
    variable qm: std_ulogic_vector(7 downto 0);
    variable qm8: std_ulogic;
    variable qmd: signed(3 downto 0);
  begin
    rin <= r;

    if de_i = '0' then
      rin.qm <= "----" & control_i;
      rin.de <= false;
      rin.terc4 <= terc4_i = '1';
      rin.qm8 <= '-';
      rin.qm_disp <= (others => '-');

    else
      pixel_word_encode(pixel_i, qm, qm8, qmd);
      rin.qm <= qm;
      rin.qm_disp <= qmd;
      rin.qm8 <= qm8;
      rin.de <= true;
      rin.terc4 <= false;
    end if;

    if not r.de then
      if r.terc4 then
        rin.dout <= terc4_encode(r.qm(3 downto 0));
      else
        rin.dc_bias <= (others => '0');
        rin.dout <= control_encode(r.qm(2 downto 0));
      end if;

    elsif r.dc_bias = 0 or r.qm_disp = 0 then
      if r.qm8 = '0' then
        rin.dout <= tmds_symbol_t("10" & not r.qm);
        rin.dc_bias <= r.dc_bias - r.qm_disp;
      else
        rin.dout <= tmds_symbol_t("01" & r.qm);
        rin.dc_bias <= r.dc_bias + r.qm_disp;
      end if;

    elsif r.qm_disp(r.qm_disp'left) = r.dc_bias(r.dc_bias'left) then
      rin.dout <= tmds_symbol_t('1' & r.qm8 & not r.qm);
      if r.qm8 = '0' then
        rin.dc_bias <= r.dc_bias - r.qm_disp;
      else
        -- Spec says + 2 * qm8, but we divide by 2
        rin.dc_bias <= r.dc_bias - r.qm_disp + 1;
      end if;

    else
      rin.dout <= tmds_symbol_t('0' & r.qm8 & r.qm);
      if r.qm8 = '0' then
        -- Spec says - 2 * ~qm8, but we divide by 2
        rin.dc_bias <= r.dc_bias + r.qm_disp - 1;
      else
        rin.dc_bias <= r.dc_bias + r.qm_disp;
      end if;
    end if;
  end process;

  symbol_o <= r.dout;

end beh;
