library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory;
use nsl_memory.lifo.all;

entity lifo_regs is
  generic(
    data_width_c : positive;
    word_count_c : positive
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    op_i : in lifo_op_t;
    data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
    data_o      : out std_ulogic_vector(data_width_c-1 downto 0);

    empty_o : out std_ulogic;
    full_o : out std_ulogic;
    free_o  : out integer range 0 to word_count_c;
    available_o : out integer range 0 to word_count_c
    );
end entity;

architecture beh of lifo_regs is

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type storage_t is array (integer range <>) of word_t;
  constant unk : word_t := (others => '-');
  
  type regs_t is
  record
    counter : integer range 0 to word_count_c;
    reg : storage_t(0 to word_count_c-1);
  end record;

  signal r, rin: regs_t;

begin
  
  regs: process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.counter <= 0;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, op_i, r, data_i)
  begin
    rin <= r;

    case op_i is
      when LIFO_OP_PUSH =>
        if r.counter /= word_count_c then
          rin.counter <= r.counter + 1;
          rin.reg <= data_i & r.reg(0 to word_count_c-2);
        end if;

      when LIFO_OP_POP =>
        if r.counter /= 0 then
          rin.counter <= r.counter - 1;
          rin.reg <= r.reg(1 to word_count_c-1) & unk;
        end if;
        
      when others =>
        null;
    end case;
  end process;

  empty_o <= '1' when r.counter = 0 else '0';
  full_o <= '1' when r.counter = word_count_c else '0';
  available_o <= r.counter;
  free_o <= word_count_c - r.counter;
  data_o <= r.reg(0);
  
end architecture;
