library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_clock_generator_from_tick is
  generic(
    tick_per_sample_c : natural range 128 to 1024 := 128
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;

    sck_o : out std_ulogic;
    ws_o  : out std_ulogic
    );
end entity;

architecture beh of i2s_clock_generator_from_tick is

  constant word_width_c : natural := tick_per_sample_c / 4;

  type regs_t is record
    word_bit_left : natural range 0 to word_width_c - 1;
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
      r.word_bit_left <= 0;
      r.sck <= '0';
      r.ws <= '0';
    end if;
  end process;

  transition : process (r, tick_i)
  begin
    rin <= r;

    if tick_i = '1' then
      rin.sck <= not r.sck;

      if r.sck = '1' then
        if r.word_bit_left /= 0 then
          rin.word_bit_left <= r.word_bit_left - 1;
        else
          rin.word_bit_left <= word_width_c - 1;
          rin.ws <= not r.ws;
        end if;
      end if;
    end if;
  end process;

  sck_o <= r.sck;
  ws_o <= r.ws;
  
end architecture;
