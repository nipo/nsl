library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep;

entity tap_test is
  port (
    chip_tck_i : in std_logic := '0';
    chip_tms_i : in std_logic := '0';
    chip_tdi_i : in std_logic := '0';
    chip_tdo_o : out std_logic
  );
end tap_test;

architecture arch of tap_test is

  signal tlr_s, rti_s, update_s, capture_s, selected_s, shift_s, tdo_s, tdi_s, tck_s: std_ulogic;

  type regs_t is
  record
    reg, shreg: std_ulogic_vector(31 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(tck_s) is
  begin
    if rising_edge(tck_s) then
      r <= rin;
    end if;
  end process;

  tr: process(capture_s, r, rti_s, selected_s, shift_s, tdi_s, tlr_s, update_s) is
  begin
    rin <= r;

    if tlr_s = '1' then
      rin.reg <= x"deadbeef";
    elsif selected_s = '1' then
      if rti_s = '1' then
        rin.reg <= std_ulogic_vector(unsigned(r.reg) + 1);
      elsif update_s = '1' then
        rin.reg <= r.shreg;
      end if;

      if capture_s = '1' then
        rin.shreg <= r.reg;
      elsif shift_s = '1' then
        rin.shreg <= tdi_s & r.shreg(r.shreg'left downto 1);
      end if;
    end if;
  end process;

  tdo_s <= r.shreg(0);
  
  inst: nsl_hwdep.jtag.jtag_user_tap
    port map(
      chip_tck_i => chip_tck_i,
      chip_tdi_i => chip_tdi_i,
      chip_tms_i => chip_tms_i,
      chip_tdo_o => chip_tdo_o,

      tdo_i(0) => tdo_s,
      selected_o(0) => selected_s,
      tdi_o => tdi_s,
      run_o => rti_s,
      shift_o => shift_s,
      capture_o => capture_s,
      update_o => update_s,
      tlr_o => tlr_s,
      tck_o => tck_s
      );

end arch;
