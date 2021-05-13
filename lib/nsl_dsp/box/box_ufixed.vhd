library ieee;
use ieee.std_logic_1164.all;

library nsl_math;
use nsl_math.fixed.all;

entity box_ufixed is
  generic(
    count_l2_c : natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in ufixed;
    out_o : out ufixed
    );
end entity;    

architecture beh of box_ufixed is

  subtype sample_t is ufixed(in_i'left downto in_i'right);
  type sample_vector is array (integer range <>) of sample_t;
  subtype acc_t is ufixed(in_i'left + count_l2_c downto in_i'right);

  type regs_t is
  record
    delay_line : sample_vector(0 to 2**count_l2_c-1);
    acc : acc_t;
  end record;

  signal r, rin : regs_t;

begin

  assert in_i'left = out_o'left and in_i'right = out_o'right
    report "Input and output data words are not the same size"
    severity failure;

  reg: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.delay_line <= (others => (others => '0'));
      r.acc <= (others => '0');
    end if;
  end process;

  transition: process(r, in_i) is
  begin
    rin.delay_line <= r.delay_line(1 to r.delay_line'right) & in_i;
    rin.acc <= r.acc
               - resize(r.delay_line(0), acc_t'left, acc_t'right)
               + resize(in_i, acc_t'left, acc_t'right);
  end process;

  out_o <= resize(shr(r.acc, count_l2_c), out_o'left, out_o'right);

end architecture;
