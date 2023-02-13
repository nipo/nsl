library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use work.timestamp.all;

entity skew_offsetter is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    reference_i: in timestamp_t;
    offset_i: in timestamp_nanosecond_offset_t;

    skewed_o: out timestamp_t
    );
end entity;

architecture beh of skew_offsetter is

  type regs_t is
  record
    reference: timestamp_t;
    offset: timestamp_nanosecond_offset_t;
    offset_m_1s: signed(timestamp_nanosecond_offset_t'left+1 downto 0);

    second, second_p1, second_m1: timestamp_second_t;
    offsetted_nano, offsetted_nano_m_1s: signed(offset_i'left+1 downto 0);
    abs_change: std_ulogic;
    
    skewed: timestamp_t;
  end record;

  signal r, rin: regs_t;

  function pos_of(v: signed; l: natural) return unsigned
  is
    alias xv: signed(v'length-1 downto 0) is v;
    variable ret: unsigned(l-1 downto 0);
    constant rl: natural := nsl_math.arith.min(v'length-1, ret'length);
  begin
    ret := (others => '0');
    ret(rl-1 downto 0) := unsigned(xv(rl-1 downto 0));
    return ret;
  end function;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.reference.second <= (others => '0');
      r.reference.nanosecond <= (others => '0');
      r.reference.abs_change <= '0';
      r.offset <= (others => '0');
      r.offset_m_1s <= (others => '0');
      r.skewed.second <= (others => '0');
      r.skewed.nanosecond <= (others => '0');
      r.skewed.abs_change <= '0';
      r.second <= (others => '0');
      r.second_p1 <= (others => '0');
      r.second_m1 <= (others => '0');
      r.offsetted_nano <= (others => '0');
      r.offsetted_nano_m_1s <= (others => '0');
      r.abs_change <= '0';
    end if;
  end process;

  transition: process(r,
                      reference_i,
                      offset_i) is
  begin
    rin <= r;

    rin.reference <= reference_i;
    rin.offset <= offset_i;
    rin.offset_m_1s <= resize(offset_i, rin.offset_m_1s'length) - 1e9;

    rin.second <= r.reference.second;
    rin.second_m1 <= r.reference.second - 1;
    rin.second_p1 <= r.reference.second + 1;
    rin.offsetted_nano <= resize(signed("0"&r.reference.nanosecond), rin.offsetted_nano'length)
                          + resize(r.offset, rin.offsetted_nano'length);
    rin.offsetted_nano_m_1s <= resize(signed("0"&r.reference.nanosecond), rin.offsetted_nano'length)
                               + resize(r.offset_m_1s, rin.offsetted_nano'length);
    rin.abs_change <= r.reference.abs_change;

    -- Theoritically, -1e9 < offsetted_nano < 2e9-1
    if r.offsetted_nano < 0 then
      rin.skewed.second <= r.second_m1;
      rin.skewed.nanosecond <= pos_of(r.offsetted_nano + 1e9, rin.skewed.nanosecond'length);
    elsif r.offsetted_nano_m_1s >= 0 then
      rin.skewed.second <= r.second_p1;
      rin.skewed.nanosecond <= pos_of(r.offsetted_nano_m_1s, rin.skewed.nanosecond'length);
    else
      rin.skewed.second <= r.second;
      rin.skewed.nanosecond <= pos_of(r.offsetted_nano, rin.skewed.nanosecond'length);
    end if;
    rin.skewed.abs_change <= r.abs_change;
  end process;

  skewed_o <= r.skewed;

end architecture;
