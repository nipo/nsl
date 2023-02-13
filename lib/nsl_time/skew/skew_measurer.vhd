library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

entity skew_measurer is
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    strobe_i : in std_ulogic := '0';
    reference_i: in timestamp_t;
    skewed_i: in timestamp_t;

    strobe_o : out std_ulogic;
    offset_o: out timestamp_nanosecond_offset_t
    );
end entity;

architecture beh of skew_measurer is

  type regs_t is
  record
    reference, skewed: timestamp_t;
    ref_strobe: std_ulogic;

    second_diff: signed(32 downto 0);
    nanosecond_diff: signed(30 downto 0);
    diff_strobe: std_ulogic;
    
    offset: signed(30 downto 0);
    offset_strobe: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.ref_strobe <= '0';
      r.diff_strobe <= '0';
      r.offset_strobe <= '0';

      r.nanosecond_diff <= (others => '0');
      r.second_diff <= (others => '0');
      r.offset <= (others => '0');
    end if;
  end process;

  transition: process(r,
                      strobe_i,
                      reference_i,
                      skewed_i) is
  begin
    rin <= r;

    rin.reference <= reference_i;
    rin.skewed <= skewed_i;
    rin.ref_strobe <= strobe_i;

    rin.nanosecond_diff <= signed(resize(r.skewed.nanosecond, rin.nanosecond_diff'length))
                           - signed(resize(r.reference.nanosecond, rin.nanosecond_diff'length));
    rin.second_diff <= signed(resize(r.skewed.second, rin.second_diff'length))
                       - signed(resize(r.reference.second, rin.second_diff'length));
    rin.diff_strobe <= r.ref_strobe;

    -- Theoritically, -1e9 < nanosecond_diff < 1e9
    if r.second_diff = 0 then
      rin.offset <= r.nanosecond_diff;
    elsif r.second_diff = -1 and r.nanosecond_diff > 0 then
      rin.offset <= r.nanosecond_diff - 1e9;
    elsif r.second_diff = 1 and r.nanosecond_diff < 0 then
      rin.offset <= r.nanosecond_diff + 1e9;
    elsif r.second_diff > 0 then
      rin.offset <= to_signed(1e9 - 1, rin.offset'length);
    else
      rin.offset <= to_signed(-1e9 + 1, rin.offset'length);
    end if;
    rin.offset_strobe <= r.diff_strobe;
  end process;

  strobe_o <= r.offset_strobe;
  offset_o <= r.offset;

end architecture;
