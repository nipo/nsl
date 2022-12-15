library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

entity pdd2_sfixed is
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i: in std_ulogic;
    set_point_i: in sfixed;
    measure_i: in sfixed;

    kp_i: in sfixed;
    kd_i: in sfixed;
    kd2_i: in sfixed;

    changed_o: out std_ulogic;
    control_o : out sfixed
    );
end entity;

architecture beh of pdd2_sfixed is

  --                     /->[*kp]->[R]->[Sat]---->[R]------------->[R]--\
  --                     |         p1              p2               p3  |
  --                     |                                             [+]-[R]--\
  --                     |                                              |  pd4  |
  -- set_point -[-]->[R]-+---->[-]->[R]-+->[*kd]->[R]---->[Sat]--->[R]--/       |
  --             ^   e0  |      |   d1  |         d2               d3          [+]->[R]-[Sat]->[R]-> control
  --             |       \->[R]-/       |                                       |    c5         c6
  --             |          do1         |                                       |
  --   measure --/                      +--->[-]->[R]->[*kdd2]->[R]->[Sat]->[R]-/
  --                                    |     |   d22           d23         d24
  --                                    \-[R]-/
  --                                     d2o2
  --
  -- Register mantissa:
  -- Re0: set_point + 1[msb]
  -- Rp1: Re0 + kp
  -- Rd2: Re0 + kd
  -- Rdo1: Re0
  -- Rd1, Rd2o2: Re0 + 1[msb]
  -- Rd22: Re0 + 2[msb]
  -- Rdo1, Rd1, Rd2o2, Rd22: Re0
  -- Rd23: Re0 + kd2
  -- Rd3, Rp3, Rp2: control + 1[lsb]
  -- Rd24, Rpd4: control + 1[msb] + 1[lsb]
  -- Rc5: control + 2[msb]
  -- Rc6: control

  subtype re0_t is sfixed(measure_i'left+1 downto measure_i'right);
  subtype rc6_t is sfixed(control_o'left downto control_o'right);
  subtype rc5_t is sfixed(control_o'left+2 downto control_o'right);
  subtype rd24_t is sfixed(control_o'left+1 downto control_o'right-1);
  subtype rpd4_t is rd24_t;
  subtype rd3_t is sfixed(control_o'left downto control_o'right-1);
  subtype rp3_t is rd3_t;
  subtype rp2_t is rd3_t;
  subtype rd23_t is sfixed(re0_t'left+kd2_i'left downto re0_t'right+kd2_i'right);
  subtype rdo1_t is re0_t;
  subtype rd1_t is sfixed(re0_t'left+1 downto re0_t'right);
  subtype rd2o2_t is rd1_t;
  subtype rd22_t is sfixed(rd1_t'left+1 downto rd1_t'right);
  subtype rd2_t is sfixed(re0_t'left+kd_i'left downto re0_t'right+kd_i'right);
  subtype rp1_t is sfixed(re0_t'left+kp_i'left downto re0_t'right+kp_i'right);

  type regs_t is
  record
    stage: std_ulogic_vector(0 to 7);
    e0: re0_t;
    c6: rc6_t;
    c5: rc5_t;
    d24: rd24_t;
    pd4: rpd4_t;
    d3: rd3_t;
    p3: rp3_t;
    p2: rp2_t;
    d23: rd23_t;
    do1: rdo1_t;
    d1: rd1_t;
    d2o2: rd2o2_t;
    d22: rd22_t;
    d2: rd2_t;
    p1: rp1_t;
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
      r.c6 <= (others => '0');
      r.c5 <= (others => '0');
      r.d24 <= (others => '0');
      r.pd4 <= (others => '0');
      r.d3 <= (others => '0');
      r.p3 <= (others => '0');
      r.p2 <= (others => '0');
      r.d23 <= (others => '0');
      r.do1 <= (others => '0');
      r.d1 <= (others => '0');
      r.d2o2 <= (others => '0');
      r.d22 <= (others => '0');
      r.d2 <= (others => '0');
      r.p1 <= (others => '0');
    end if;
  end process;

  transition: process(r, valid_i, kp_i, kd_i, kd2_i, set_point_i, measure_i) is
    variable en: std_ulogic_vector(r.stage'range);
  begin
    assert set_point_i'length = 0
      or (set_point_i'left = measure_i'left and set_point_i'right = measure_i'right)
      report "Set point and measurement magniture should be the same or set point should be zero"
      severity failure;

    rin <= r;

    en := valid_i & r.stage(0 to r.stage'right-1);
    rin.stage <= en;

    if en(0) = '1' then
      if set_point_i'length = 0 then
        rin.e0 <= neg_extend(measure_i);
      else
        rin.e0 <= sub_extend(set_point_i, measure_i);
      end if;
    end if;

    if en(1) = '1' then
      rin.p1 <= mul(r.e0, kp_i, rin.p1'left, rin.p1'right);
      rin.do1 <= r.e0;
      rin.d1 <= sub_extend(r.e0, r.do1);
    end if;

    if en(2) = '1' then
      rin.d2o2 <= r.d1;
      rin.d22 <= sub_extend(r.d1, r.d2o2);
      rin.d2 <= mul(r.d1, kd_i, rin.d2'left, rin.d2'right);
      rin.p2 <= resize_saturate(r.p1, rin.p2'left, rin.p2'right);
    end if;

    if en(3) = '1' then
      rin.p3 <= r.p2;
      rin.d3 <= resize_saturate(r.d2, r.d3'left, r.d3'right);
      rin.d23 <= mul(r.d22, kd_i, rin.d23'left, rin.d23'right);
    end if;

    if en(4) = '1' then
      rin.pd4 <= add_extend(r.d3, r.p3);
      rin.d24 <= resize_saturate(r.d23, r.d24'left, r.d24'right);
    end if;

    if en(5) = '1' then
      rin.c5 <= add_extend(r.pd4, r.d24)(rin.c5'left downto rin.c5'right);
    end if;

    if en(6) = '1' then
      rin.c6 <= resize_saturate(r.c5, rin.c6'left, rin.c6'right);
    end if;
  end process;

  changed_o <= r.stage(r.stage'right);
  control_o <= r.c6;
  
end architecture;

