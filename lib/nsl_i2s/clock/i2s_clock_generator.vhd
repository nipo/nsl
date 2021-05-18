library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_clock_generator is
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    sck_div_m1_i    : in unsigned;
    word_width_m1_i : in unsigned;

    sck_o : out std_ulogic;
    ws_o  : out std_ulogic
    );
end entity;

architecture beh of i2s_clock_generator is
  
  type regs_t is record
    sck_div : unsigned(sck_div_m1_i'range);
    word_bit_left : unsigned(word_width_m1_i'range);
    sck : std_ulogic;
    ws : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin
  
  ck : process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.sck_div <= (others => '0');
      r.word_bit_left <= (others => '0');
      r.sck <= '0';
      r.ws <= '0';
    end if;
  end process;

  transition : process (r, sck_div_m1_i, word_width_m1_i)
  begin
    rin <= r;

    if r.sck_div /= 0 then
      rin.sck_div <= r.sck_div - 1;
    else
      rin.sck_div <= sck_div_m1_i;
      rin.sck <= not r.sck;

      if r.sck = '1' then
        if r.word_bit_left /= 0 then
          rin.word_bit_left <= r.word_bit_left - 1;
        else
          rin.word_bit_left <= word_width_m1_i;
          rin.ws <= not r.ws;
        end if;
      end if;
    end if;
  end process;

  sck_o <= r.sck;
  ws_o <= r.ws;
  
end architecture;
