library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;
use nsl_math.fixed.all;

entity sc202_driver is
  generic(
    voltage_i_scale_c: real := 1.0
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    voltage_i : in ufixed;
    
    vsel_o : out std_ulogic_vector(3 downto 0)
    );
end entity;

architecture beh of sc202_driver is

  function msb(v: real) return integer
  is
    variable ret : integer := 0;
  begin
    assert v > 0.0
      report "This function is undefined for <= 0.0"
      severity failure;

    return integer(log2(v));
  end function;

  constant sc202_smallest_step : real := 0.05;
  constant sc202_full_range : real := 3.3;

  constant voltage_left: integer := msb(sc202_full_range / voltage_i_scale_c);
  constant voltage_right: integer := msb(sc202_smallest_step / voltage_i_scale_c);

  signal voltage : ufixed(voltage_left downto voltage_right);
  
  type state_t is (
    ST_IDLE,
    ST_CHANGE
    );
  
  type regs_t is
  record
    vsel, vsel_next: std_ulogic_vector(3 downto 0);
    state: state_t;
  end record;

  signal r, rin: regs_t;

  subtype vsel_t is std_ulogic_vector(3 downto 0);

  function to_vsel(voltage: real) return vsel_t
  is
  begin
    if voltage >= 3.3  then return "1111"; end if;
    if voltage >= 3.0  then return "1110"; end if;
    if voltage >= 2.8  then return "1101"; end if;
    if voltage >= 2.5  then return "1100"; end if;
    if voltage >= 2.2  then return "1011"; end if;
    if voltage >= 2.0  then return "1010"; end if;
    if voltage >= 1.9  then return "1001"; end if;
    if voltage >= 1.85 then return "1000"; end if;
    if voltage >= 1.8  then return "0111"; end if;
    if voltage >= 1.6  then return "0110"; end if;
    if voltage >= 1.5  then return "0101"; end if;
    if voltage >= 1.4  then return "0100"; end if;
    if voltage >= 1.2  then return "0011"; end if;
    if voltage >= 1.0  then return "0010"; end if;
    if voltage >= 0.8  then return "0001"; end if;
    return "0000";
  end function;

  type vsel_vector is array(integer range <>) of vsel_t;

  function vsel_gen(l, r: integer; scale: real) return vsel_vector
  is
    variable ret: vsel_vector(0 to 2**(l-r+1)-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_vsel(real(i) * (2.0 ** real(r)) * scale);
    end loop;
    return ret;
  end function;

  constant vsel_c : vsel_vector := vsel_gen(voltage'left,
                                            voltage'right,
                                            voltage_i_scale_c);
  
begin

  -- Resize input voltage to a range where we have enough precision
  voltage <= resize(voltage_i, voltage_left, voltage_right);
  
  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.vsel <= (others => '0');
      r.vsel_next <= (others => '0');
    end if;
  end process;

  transition: process(r, voltage) is
    variable idx: unsigned(voltage'length-1 downto 0);
  begin
    rin <= r;

    idx := to_unsigned(voltage);
    rin.vsel_next <= vsel_c(to_integer(idx));
    
    case r.state is
      when ST_IDLE =>
        if r.vsel /= r.vsel_next then
          rin.state <= ST_CHANGE;
        end if;

      when ST_CHANGE =>
        rin.vsel <= r.vsel_next;
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    case r.state is
      when ST_IDLE =>
        vsel_o <= r.vsel;

      when ST_CHANGE =>
        vsel_o <= r.vsel or r.vsel_next;
    end case;
  end process;

end architecture;

