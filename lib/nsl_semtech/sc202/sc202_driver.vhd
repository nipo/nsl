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

  function to_vsel(voltage: real) return std_ulogic_vector
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

  -- Iterate over all possible set-point values.  This builds a lookup
  -- table from input ufixed to output control bits.
  -- If more bits than necessary are available as inputs, optimizer
  -- should cancel them away.
  function to_vsel(voltage: ufixed; scale: real) return std_ulogic_vector
  is
    variable vf: ufixed(voltage'range);
  begin
    for i in 0 to 2**voltage'length - 1
    loop
      vf := ufixed(to_unsigned(i, voltage'length));
      if vf = voltage then
        return to_vsel(to_real(vf) * scale);
      end if;
    end loop;
    return "0000";
  end function;
  
begin

  -- Resize input voltage to a range where we have enough precision
  voltage <= resize(voltage_i, voltage_left, voltage_right);
  
  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.vsel <= (others => '0');
      r.vsel_next <= (others => '0');
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, voltage) is
  begin
    rin <= r;

    rin.vsel_next <= to_vsel(voltage, voltage_i_scale_c);
    
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

