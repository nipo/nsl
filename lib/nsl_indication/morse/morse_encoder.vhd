library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_indication, nsl_math;

entity morse_encoder is
  generic (
    clock_rate_c : positive;
    symbol_per_minute_c : positive := 512;
    inter_character_duration_c : positive := 1;
    inter_word_duration_c : positive := 7
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    valid_i : in std_ulogic;
    last_i : in std_ulogic;
    ready_o : out std_ulogic;
    data_i : in nsl_indication.morse.morse_character_t;

    morse_o : out std_ulogic
    );
end entity;

architecture beh of morse_encoder is

  constant symbol_period : natural := clock_rate_c * 60 / symbol_per_minute_c;
  constant duration_max : natural := nsl_math.arith.max(inter_word_duration_c, inter_character_duration_c);
  constant tee_duration : natural := 1;
  constant tah_duration : natural := 3;

  type state_t is (
    ST_RESET,
    ST_TAKE,
    ST_ROUTE,
    ST_SYM,
    ST_PAUSE,
    ST_INTER
    );
  
  type regs_t is
  record
    shreg : nsl_indication.morse.morse_character_t;
    prescaler : natural range 0 to symbol_period - 1;
    duration : natural range 0 to duration_max;
    last : boolean;
    state : state_t;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, valid_i, last_i, data_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAKE;

      when ST_TAKE =>
        if valid_i = '1' then
          rin.last <= last_i = '1';
          rin.shreg <= data_i;
          rin.state <= ST_ROUTE;
        end if;

      when ST_ROUTE =>
        if r.shreg = "00000001" or r.shreg = "00000000" then
          rin.state <= ST_INTER;
          if r.last then
            rin.duration <= inter_word_duration_c - tee_duration - 1;
          else
            rin.duration <= inter_character_duration_c - tee_duration - 1;
          end if;
        else
          rin.state <= ST_SYM;
          rin.shreg <= '0' & r.shreg(7 downto 1);

          if r.shreg(0) = '1' then
            rin.duration <= tah_duration - 1;
          else
            rin.duration <= tee_duration - 1;
          end if;
        end if;
          
        rin.prescaler <= symbol_period - 1;

      when ST_SYM | ST_PAUSE | ST_INTER =>
        if r.prescaler /= 0 then
          rin.prescaler <= r.prescaler - 1;
        elsif r.duration /= 0 then
          rin.prescaler <= symbol_period - 1;
          rin.duration <= r.duration - 1;
        elsif r.state = ST_SYM then
          rin.state <= ST_PAUSE;
          rin.prescaler <= symbol_period - 1;
          rin.duration <= tee_duration - 1; -- Inter symbol
        elsif r.state = ST_PAUSE then
          rin.state <= ST_ROUTE;
        elsif r.state = ST_INTER then
          rin.state <= ST_TAKE;
        end if;
    end case;
  end process;

  morse_o <= '1' when r.state = ST_SYM else '0';
  ready_o <= '1' when r.state = ST_TAKE else '0';
  
end architecture;
