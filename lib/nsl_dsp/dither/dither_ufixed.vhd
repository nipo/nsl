library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use nsl_math.fixed.all;

entity dither_ufixed is
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    in_valid_i : in std_ulogic;
    in_i : in ufixed;
    out_ready_i : in std_ulogic;
    out_o : out ufixed
    );
end entity;

architecture beh of dither_ufixed is

  subtype acc_t is ufixed(in_i'range);
  constant unit_c: ufixed(out_o'range) := (out_o'right => '1', others => '0');
  
  type regs_t is
  record
    in_value: acc_t;
    acc : acc_t;
    out_value : ufixed(out_o'range);
  end record;

  signal r, rin : regs_t;
  signal box_out_s, box_in_s: acc_t;
  
begin

  assert in_i'left = out_o'left and in_i'right < out_o'right
    report "Input and output data words should have same MSB and input should be longer"
    severity failure;
  
  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.acc <= (others => '0');
    end if;
  end process;

  box: work.box.box_ufixed
    generic map(
      count_l2_c => out_o'right - in_i'right
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      valid_i => out_ready_i,
      in_i => box_in_s,
      out_o => box_out_s
      );

  transition: process(r, in_i, in_valid_i, box_out_s, out_ready_i) is
  begin
    rin <= r;

    if in_valid_i = '1' then
      rin.in_value <= resize(in_i, rin.in_value'left, rin.in_value'right);
    end if;

    if box_out_s < r.in_value and r.in_value(out_o'range) /= (out_o'range => '1') then
      r.out_value <= resize(r.in_value, r.out_value'left, r.out_value'right) + unit_c;
    else
      r.out_value <= resize(r.in_value, r.out_value'left, r.out_value'right);
    end if;
  end process;

  box_in_s(r.out_value'range) <= r.out_value;
  box_in_s(r.out_value'right-1 downto box_in_s'right) <= (others => '0');
  out_o <= r.out_value;

end architecture;
