library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_signal_generator;
use nsl_math.fixed.all;

entity nco_sinus is
  generic (
    scale_c : real := 1.0;
    trim_bits_c : natural := 0
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;
    angle_increment_i : in ufixed;
    value_o : out sfixed
    );
end entity;    

architecture beh of nco_sinus is

  type regs_t is
  record
    angle_acc : ufixed(-1 downto angle_increment_i'right);
  end record;

  signal r, rin: regs_t;
  signal s_angle: ufixed(r.angle_acc'left downto r.angle_acc'right+trim_bits_c);

begin

  assert angle_increment_i'left <= -1
    report "angle_i'left must be <= -1"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.angle_acc <= (others => '0');
    end if;
  end process;

  transition: process(r, angle_increment_i) is
  begin
    rin <= r;

    rin.angle_acc <= r.angle_acc + resize(angle_increment_i, r.angle_acc'left, r.angle_acc'right);
  end process;

  s_angle <= r.angle_acc(s_angle'range);

  sinus: nsl_signal_generator.sinus.sinus_stream
    generic map(
      scale_c => scale_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      angle_i => s_angle,
      value_o => value_o
      );
  
end architecture;
