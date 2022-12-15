library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

entity pid_sfixed is
  generic(
    ni_c: positive := 8
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i: in std_ulogic;
    set_point_i: in sfixed;
    measure_i: in sfixed;

    kp_i: in sfixed;
    ki_i: in sfixed := nasf;
    kd_i: in sfixed := nasf;

    changed_o: out std_ulogic;
    control_o : out sfixed
    );
end entity;

architecture beh of pid_sfixed is

  --                     /->[*kp]->[R]------->[R]----[Sat]--->[R]--\
  --                     |         p1         p2              p3   |
  --                     |                                         |
  --                     |                                        [+]->[Sat]-[R]-> control
  -- set_point -[-]->[R]-+->[*ki]->[R]->[+]-[Sat]->[R]-+----\      |         c4
  --             ^   e0  |         i1    ^         i2  |    |      |
  --             |       |               \-------------/   [+]-[R]-/
  --             |       |                                  |  di3
  --   measure --/       \->[*kd]->[R]-+---->[-]-[Sat]->[R]-/
  --                               d1  |      ^         d2
  --                                   \->[R]-/
  --                                      da2
  --
  -- Register mantissa:
  -- Re0: set_point + 1[msb]
  -- Rp1, Rp2: Re0 + kp
  -- Ri1: Re0 + ki
  -- Rd1, Rda2: Re0 + kd
  -- Ri2: Re0 + ki + ni[msb]
  -- Rd2: control + 1[lsb]
  -- Rp3, Rdi3: control + 1[msb] + 2[lsb]
  -- Rc4: control

  subtype rc4_t is sfixed(control_o'left downto control_o'right);
  subtype re0_t is sfixed(set_point_i'left+1 downto set_point_i'right);
  subtype rp1_t is sfixed(re0_t'left+kp_i'left downto re0_t'right+kp_i'right);
  subtype rp2_t is rp1_t;
  subtype ri1_t is sfixed(re0_t'left+ki_i'left downto re0_t'right+ki_i'right);
  subtype ri2_t is sfixed(re0_t'left+ki_i'left+ni_c downto re0_t'right+ki_i'right);
  subtype rd1_t is sfixed(re0_t'left+kd_i'left downto re0_t'right+kd_i'right);
  subtype rda2_t is rd1_t;
  subtype rd2_t is sfixed(rc4_t'left downto rc4_t'right-2);
  subtype rp3_t is sfixed(rc4_t'left+1 downto rc4_t'right-2);
  subtype rdi3_t is rp3_t;

  type regs_t is
  record
    stage: std_ulogic_vector(0 to 5);
    e0: re0_t;
    c4: rc4_t;
    p1: rp1_t;
    p2: rp2_t;
    p3: rp3_t;
    i1: ri1_t;
    i2: ri2_t;
    d1: rd1_t;
    da2: rda2_t;
    d2: rd2_t;
    di3: rdi3_t;
  end record;

  signal r, rin: regs_t;
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.stage <= (others => '0');
      r.e0 <= (others => '0');
      r.c4 <= (others => '0');
      r.p1 <= (others => '0');
      r.p2 <= (others => '0');
      r.p3 <= (others => '0');
      r.i1 <= (others => '0');
      r.i2 <= (others => '0');
      r.d1 <= (others => '0');
      r.da2 <= (others => '0');
      r.d2 <= (others => '0');
      r.di3 <= (others => '0');
    end if;
  end process;

  transition: process(r, valid_i, kp_i, ki_i, kd_i, set_point_i, measure_i) is
    variable en: std_ulogic_vector(r.stage'range);
  begin
    assert set_point_i'left = measure_i'left and set_point_i'right = measure_i'right
      report "Set point and measurement magniture should be the same"
      severity failure;

    rin <= r;

    en := valid_i & r.stage(0 to r.stage'right-1);
    rin.stage <= en;

    if en(0) = '1' then
      rin.e0 <= sub_extend(set_point_i, measure_i);
    end if;

    if en(1) = '1' then
      rin.p1 <= mul(r.e0, kp_i, rin.p1'left, rin.p1'right);
      rin.i1 <= mul(r.e0, ki_i, rin.i1'left, rin.i1'right);
      rin.d1 <= mul(r.e0, kd_i, rin.d1'left, rin.d1'right);
    end if;

    if en(2) = '1' then
      rin.p2 <= r.p1;

      rin.i2 <= add_saturate(r.i2, resize(r.i1, r.i2'left, r.i2'right));
      rin.da2 <= r.d1;
      rin.d2 <= resize_saturate(add_saturate(r.da2, r.d1), rin.d2'left, rin.d2'right);
    end if;

    if en(3) = '1' then
      rin.p3 <= resize_saturate(r.p2, rin.p3'left, rin.p3'right);
      rin.di3 <= add_extend(resize_saturate(r.i2, r.d2'left, r.d2'right),
                            r.d2);
    end if;

    if en(4) = '1' then
      rin.c4 <= resize_saturate(add_saturate(r.p3, r.di3), rin.c4'left, rin.c4'right);
    end if;
  end process;

  changed_o <= r.stage(r.stage'right);
  control_o <= r.c4;
  
end architecture;

