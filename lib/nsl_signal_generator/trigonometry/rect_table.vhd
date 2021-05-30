library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_data, nsl_memory;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity rect_table is
  generic(
    scale_c : real := 1.0
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    ready_o : out std_ulogic;
    valid_i : in std_ulogic;

    x_o : out sfixed;
    y_o : out sfixed;
    valid_o : out std_ulogic;
    ready_i : in std_ulogic
    );
end rect_table;

architecture beh of rect_table is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_PREPARE,
    ST_READ,
    ST_OPP,
    ST_RESP
    );

  subtype angle_t is ufixed(angle_i'range);
  subtype address_t is unsigned(-angle_i'right - 3 downto 0);
  
  type regs_t is
  record
    state : state_t;
    angle : ufixed(-1 downto angle_i'right);
    x_address, y_address : address_t;
    x_aopp, y_aopp : boolean;
    x_opp, y_opp : boolean;
    x : sfixed(x_o'range);
    y : sfixed(y_o'range);
  end record;

  -- Little trick: Store cos(x) for x in [0 .. π/2). This way, when we
  -- have an overflow on addresses, value is expected to be 0, and we
  -- do not have to store a specific constant.  This is particularily
  -- useful when scale is not 1.0 exactly.
  function fourth_cos(ar: integer; scale : real)
    return real_vector
  is
    variable turns_r : real;
    variable ret : real_vector(0 to (2 ** (-ar-2)) - 1);
  begin
    each_angle: for i in ret'range
    loop
      turns_r := real(i) * (2.0 ** ar);
      ret(i) := cos(turns_r * math_2_pi) * scale;
    end loop;
    return ret;
  end function;

  signal r, rin: regs_t;
  signal s_read : std_ulogic;
  constant xyl : integer := nsl_math.arith.max(x_o'left, y_o'left);
  constant xyr : integer := nsl_math.arith.min(x_o'right, y_o'right);
  signal x_uvalue, y_uvalue : ufixed(xyl-1 downto xyr);
  signal x_svalue, y_svalue : sfixed(xyl downto xyr);
  
begin

  assert angle_i'left >= -1
    report "angle_i'left must be >= -1"
    severity failure;

  assert angle_i'right <= -4
    report "angle_i'right must be <= -4, or this component is useless"
    severity failure;
  
  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  x_svalue <= sfixed("0" & x_uvalue);
  y_svalue <= sfixed("0" & y_uvalue);
  
  transition: process(r, valid_i, ready_i, angle_i, x_svalue, y_svalue)
    variable x_aopp, y_aopp: boolean;
    variable angle_addr : address_t;
  begin
    rin <= r;

    angle_addr := unsigned(to_suv(r.angle(-3 downto r.angle'right)));
    x_aopp := false;
    y_aopp := false;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          rin.state <= ST_PREPARE;
          rin.angle <= angle_i(-1 downto angle_i'right);
        end if;

      when ST_PREPARE =>
        rin.x_opp <= false;
        rin.y_opp <= false;
        rin.state <= ST_READ;

        if r.angle(-1) = '0' then
          if r.angle(-2) = '0' then
            -- angle between 0 and π/2,
            -- x is direct table lookup
            -- y is opposed table lookup
            y_aopp := true;
          else
            -- angle between π/2 and π,
            -- -x is opposed table lookup
            -- y is direct table lookup
            x_aopp := true;
            rin.x_opp <= true;
          end if;
        else
          if r.angle(-2) = '0' then
            -- angle between π and 3π/4,
            -- -x is direct table lookup
            -- -y is opposed table lookup
            y_aopp := true;
            rin.x_opp <= true;
            rin.y_opp <= true;
          else
            -- angle between 3π/4 and 2π,
            -- x is opposed table lookup
            -- -y is direct table lookup
            x_aopp := true;
            rin.y_opp <= true;
          end if;
        end if;

        rin.x_aopp <= x_aopp;
        rin.y_aopp <= y_aopp;

        if x_aopp then
          rin.x_address <= not angle_addr + 1;
        else
          rin.x_address <= angle_addr;
        end if;

        if y_aopp then
          rin.y_address <= not angle_addr + 1;
        else
          rin.y_address <= angle_addr;
        end if;

      when ST_READ =>
        rin.state <= ST_OPP;

      when ST_OPP =>
        if r.x_aopp and r.x_address = 0 then
          rin.x <= (others => '0');
        elsif r.x_opp then
          rin.x <= resize_saturate(-x_svalue, rin.x'left, rin.x'right);
        else
          rin.x <= resize_saturate(x_svalue, rin.x'left, rin.x'right);
        end if;

        if r.y_aopp and r.y_address = 0 then
          rin.y <= (others => '0');
        elsif r.y_opp then
          rin.y <= resize_saturate(-y_svalue, rin.y'left, rin.y'right);
        else
          rin.y <= resize_saturate(y_svalue, rin.y'left, rin.y'right);
        end if;

        rin.state <= ST_RESP;

      when ST_RESP =>
        if ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    valid_o <= '0';
    ready_o <= '0';
    s_read <= '0';

    x_o <= r.x;
    y_o <= r.y;

    case r.state is
      when ST_IDLE =>
        ready_o <= '1';

      when ST_RESP =>
        valid_o <= '1';

      when ST_READ =>
        s_read <= '1';

      when others =>
        null;
    end case;
  end process;

  cos_table: nsl_memory.rom_fixed.rom_ufixed_2p
    generic map(
      values_c => fourth_cos(angle_i'right, scale_c)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      a_read_i => s_read,
      a_address_i => r.x_address,
      a_value_o => x_uvalue,
      
      b_read_i => s_read,
      b_address_i => r.y_address,
      b_value_o => y_uvalue
      );

end architecture;
