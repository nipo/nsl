library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tmds.all;

entity tmds_decoder is
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    symbol_i : in tmds_symbol_t;

    de_o : out std_ulogic;
    pixel_o : out unsigned(7 downto 0);

    terc4_o : out std_ulogic;
    control_o : out std_ulogic_vector(3 downto 0)
    );
end tmds_decoder;

architecture beh of tmds_decoder is

  type regs_t is
  record
    data: std_ulogic_vector(7 downto 0);
    qw8: std_ulogic;

    de_o : std_ulogic;
    pixel_o : unsigned(7 downto 0);
    terc4_o : std_ulogic;
    control_o : std_ulogic_vector(3 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.data <= (others => '0');
      r.qw8 <= '0';
    end if;
  end process;
  
  transition: process(r, symbol_i) is
    variable inv: std_ulogic_vector(7 downto 0);
  begin
    rin <= r;

    case symbol_i(9 downto 8) is
      when "00"   => inv := "10101010";
      when "01"   => inv := "00000000";
      when "10"   => inv := "01010101";
      when others => inv := "11111111";
    end case;
    inv := inv xor std_ulogic_vector(symbol_i(7 downto 0));
    rin.data <= inv xor (inv(6 downto 0) & "0");
    rin.qw8 <= symbol_i(8);

    rin.de_o <= '1';
    rin.pixel_o <= unsigned(r.data);

    case r.data is
      when x"5b" => rin.terc4_o <= '1'; rin.control_o <= x"0";
      when x"5a" => rin.terc4_o <= '1'; rin.control_o <= x"1";
      when x"d3" => rin.terc4_o <= '1'; rin.control_o <= x"2";
      when x"d9" => rin.terc4_o <= '1'; rin.control_o <= x"3";
      when x"93" => rin.terc4_o <= '1'; rin.control_o <= x"4";
      when x"22" => rin.terc4_o <= '1'; rin.control_o <= x"5";
      when x"92" => rin.terc4_o <= '1'; rin.control_o <= x"6";
      when x"44" => rin.terc4_o <= '1'; rin.control_o <= x"7";
      when x"ab" => rin.terc4_o <= '1'; rin.control_o <= x"8";
      when x"4b" => rin.terc4_o <= '1'; rin.control_o <= x"9";
      when x"a4" => rin.terc4_o <= '1'; rin.control_o <= x"a";
      when x"b5" => rin.terc4_o <= '1'; rin.control_o <= x"b";
      when x"6d" => rin.terc4_o <= '1'; rin.control_o <= x"c";
      when x"6c" => rin.terc4_o <= '1'; rin.control_o <= x"d";
      when x"a5" => rin.terc4_o <= '1'; rin.control_o <= x"e";
      when x"ba" => rin.terc4_o <= '1'; rin.control_o <= x"f";
      when others => rin.terc4_o <= '0'; rin.control_o <= "----";
    end case;

    if (r.data(7 downto 1) = "1111110" or r.data(7 downto 1) = "0000001")
      and r.qw8 = r.data(7) then
      rin.de_o <= '0';
      rin.control_o(0) <= r.data(1);
      rin.control_o(1) <= not r.data(0);
    end if;
  end process;

  de_o <= r.de_o;
  terc4_o <= r.terc4_o;
  pixel_o <= r.pixel_o;
  control_o <= r.control_o;

end beh;
