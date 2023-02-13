library ieee;
use ieee.std_logic_1164.all;

library nsl_math, work;
use nsl_math.fixed.all;

entity box_sfixed is
  generic(
    count_l2_c : natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i : in std_ulogic := '1';
    in_i : in sfixed;
    out_o : out sfixed
    );
end entity;    

architecture beh of box_sfixed is

  subtype acc_t is sfixed(in_i'left + count_l2_c downto in_i'right);
  subtype dacc_t is sfixed(in_i'left downto in_i'right - count_l2_c);

  type regs_t is
  record
    acc : acc_t;
  end record;

  signal r, rin : regs_t;
  signal ready_s: std_ulogic;
  signal oacc_s : dacc_t;
  signal in_i_s, delayed_s: std_ulogic_vector(in_i'length-1 downto 0);

begin

  assert in_i'left = out_o'left and in_i'right >= out_o'right
    report "Input/output should have same LSB, output may have more bits"
    severity failure;

  reg: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.acc <= (others => '0');
    end if;
  end process;

  delay_line: work.delay_line.delay_line_memory
    generic map(
      data_width_c => in_i'length,
      cycles_c => 2 ** count_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      ready_o => ready_s,
      valid_i => valid_i,
      data_i => in_i_s,
      data_o => delayed_s
      );

  in_i_s <= to_suv(in_i);
  
  transition: process(r, in_i, delayed_s, valid_i, ready_s) is
    variable delayed: sfixed(in_i'range);
  begin
    rin <= r;

    delayed := sfixed(delayed_s);

    if valid_i = '1' and ready_s = '1' then
      rin.acc <= r.acc
                 - resize(delayed, acc_t'left, acc_t'right)
                 + resize(in_i, acc_t'left, acc_t'right);
    end if;
  end process;

  oacc_s <= r.acc;
  out_o <= resize(oacc_s, out_o'left, out_o'right);

end architecture;
