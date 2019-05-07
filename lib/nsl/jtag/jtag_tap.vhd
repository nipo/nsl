library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity jtag_tap is
  generic(
    ir_len : natural
    );
  port(
    tck_i  : in  std_ulogic;
    tdi_i  : in  std_ulogic;
    tdo_o  : out std_ulogic;
    tms_i  : in  std_ulogic;
    trst_i : in  std_ulogic := '0';

    default_instruction_i   : in  std_ulogic_vector(ir_len - 1 downto 0) := (others => '1');
    ir_o          : out std_ulogic_vector(ir_len - 1 downto 0);
    ir_out_i      : in std_ulogic_vector(ir_len - 1 downto 2); -- "01" implicit at LSB

    reset_o       : out std_ulogic;
    run_o         : out std_ulogic;
    dr_capture_o  : out std_ulogic;
    dr_shift_o    : out std_ulogic;
    dr_update_o   : out std_ulogic;
    dr_tdi_o       : out std_ulogic;
    dr_tdo_i      : in  std_ulogic
    );
end entity;

architecture rtl of jtag_tap is

  signal ir, ir_shreg: std_ulogic_vector(ir_len - 1 downto 0);

  signal s_reset      : std_ulogic;
  signal s_ir_capture : std_ulogic;
  signal s_ir_shift   : std_ulogic;
  signal s_ir_update  : std_ulogic;
  signal s_dr_shift   : std_ulogic;

begin

  shreg: process(tck_i)
  begin
    if rising_edge(tck_i) then
      if s_ir_capture = '1' then
        ir_shreg <= ir_out_i & "01";
      end if;

      if s_reset = '1' then
        ir <= default_instruction_i;
      elsif s_ir_update = '1' then
        ir <= ir_shreg;
      end if;
      
      if s_ir_shift = '1' then
        ir_shreg <= tdi_i & ir_shreg(ir_shreg'left downto 1);
      end if;
    end if;
  end process;

  tdo_gen: process(tck_i)
  begin
    if falling_edge(tck_i) then
      if s_ir_shift = '1' then
        tdo_o <= ir_shreg(0);
      elsif s_dr_shift = '1' then
        tdo_o <= dr_tdo_i;
      else
        tdo_o <= 'Z';
      end if;
    end if;
  end process;
  
  ir_o <= ir;
  dr_tdi_o <= tdi_i;
  reset_o <= s_reset;
  dr_shift_o <= s_dr_shift;
  
  controller: nsl.jtag.jtag_tap_controller
    port map(
      tck_i => tck_i,
      tms_i => tms_i,
      trst_i => trst_i,
      reset_o => s_reset,
      run_o => run_o,
      ir_capture_o => s_ir_capture,
      ir_shift_o => s_ir_shift,
      ir_update_o => s_ir_update,
      dr_capture_o => dr_capture_o,
      dr_shift_o => s_dr_shift,
      dr_update_o => dr_update_o
      );

end architecture;
