library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity intradomain_counter is
  generic(
    width_c : positive;

    min_c : unsigned;
    max_c : unsigned;
    reset_c : unsigned
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    increment_i : in std_ulogic;
    value_o  : out unsigned(width_c-1 downto 0);
    next_o : out unsigned(width_c-1 downto 0);
    wrap_o : out std_ulogic
    );
end entity;

architecture rtl of intradomain_counter is

  type regs_t is
  record
    cur_val, next_val : unsigned(width_c-1 downto 0);
    wrapping : std_ulogic;
  end record;

  signal r, rin : regs_t;

  constant min_val_c : unsigned(width_c-1 downto 0) := resize(min_c, width_c);
  constant max_val_c : unsigned(width_c-1 downto 0) := resize(max_c, width_c);
  constant reset_val_c : unsigned(width_c-1 downto 0) := resize(reset_c, width_c);
  
  function increment(value : in unsigned(width_c-1 downto 0))
    return unsigned
  is
    variable enlarged : unsigned(width_c downto 0);
  begin
    -- Have a shortcut for usual register wrapping
    if min_val_c = (min_val_c'range => '0') and max_val_c = (max_val_c'range => '1') then
      return value + 1;
    end if;

    if value = max_val_c then
      return min_val_c;
    else
      return value + 1;
    end if;
  end function;

  function increment_wrap(value : in unsigned(width_c-1 downto 0))
    return std_ulogic
  is
    variable enlarged : unsigned(width_c downto 0);
  begin
    enlarged := "0" & value;

    -- Have a shortcut for usual register wrapping
    if min_val_c = (min_val_c'range => '0') and max_val_c = (max_val_c'range => '1') then
      enlarged := enlarged + 1;
      return enlarged(width_c);
    end if;

    if value = max_val_c then
      return '1';
    else
      return '0';
    end if;
  end function;
  
begin

  assert min_val_c <= reset_val_c
      report "Reset value must be greater or equal to minimum value"
      severity failure;

  assert min_val_c <= max_val_c
      report "Maximum value must be greater or equal to minimum value"
      severity failure;

  assert reset_val_c <= max_val_c
      report "Reset value must be lower or equal to maximum value"
      severity failure;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.cur_val <= reset_val_c;
        r.next_val <= increment(reset_val_c);
        r.wrapping <= increment_wrap(reset_val_c);
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process(r, increment_i)
  begin
    rin <= r;

    if increment_i = '1' then
      rin.cur_val <= r.next_val;
      rin.next_val <= increment(r.next_val);
      rin.wrapping <= increment_wrap(r.next_val);
    end if;
  end process;

  value_o <= r.cur_val;
  next_o <= r.next_val;
  wrap_o <= r.wrapping;

end rtl;
