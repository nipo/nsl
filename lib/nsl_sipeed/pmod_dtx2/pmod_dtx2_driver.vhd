library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_digilent, nsl_indication;
  
entity pmod_dtx2_driver is
  generic(
    clock_i_hz_c: integer;
    blink_rate_hz_c: integer := 100
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    
    value_i: in nsl_indication.seven_segment.seven_segment_vector(0 to 1);
    pmod_io: inout nsl_digilent.pmod.pmod_double_t
    );
end entity;

architecture beh of pmod_dtx2_driver is

  constant counter_max_t : integer := clock_i_hz_c / blink_rate_hz_c / 2;
  
  type regs_t is
  record
    left: integer range 0 to counter_max_t-1;
    sel: std_ulogic;
    val: nsl_indication.seven_segment.seven_segment_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.left <= 0;
      r.sel <= '0';
    end if;
  end process;

  transition: process(r, value_i) is
  begin
    rin <= r;

    if r.left /= 0 then
      rin.left <= r.left - 1;
    else
      rin.left <= counter_max_t-1;
      rin.sel <= not r.sel;
      if r.sel = '0' then
        rin.val <= value_i(0);
      else
        rin.val <= value_i(1);
      end if;
    end if;
  end process;

  pmod_io(1) <= not r.val(5);
  pmod_io(2) <= not r.val(4);
  pmod_io(3) <= not r.val(1);
  pmod_io(4) <= not r.val(2);
  pmod_io(5) <= not r.val(6);
  pmod_io(6) <= not r.val(3);
  pmod_io(7) <= not r.val(0);
  pmod_io(8) <= not r.sel;

end architecture;
