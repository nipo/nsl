library ieee;
use ieee.std_logic_1164.all;

entity tap_controller is
  port(
    tck_i  : in  std_ulogic;
    tms_i  : in  std_ulogic;
    trst_i : in  std_ulogic := '1';

    reset_o      : out std_ulogic;
    run_o        : out std_ulogic;
    ir_capture_o : out std_ulogic;
    ir_shift_o   : out std_ulogic;
    ir_update_o  : out std_ulogic;
    dr_capture_o : out std_ulogic;
    dr_shift_o   : out std_ulogic;
    dr_update_o  : out std_ulogic
    );
end entity;

architecture rtl of tap_controller is

  type state_t is (
    ST_EXIT2_DR,
    ST_EXIT1_DR,
    ST_SHIFT_DR,
    ST_PAUSE_DR,
    ST_SELECT_IR,
    ST_UPDATE_DR,
    ST_CAPTURE_DR,
    ST_SELECT_DR,
    ST_EXIT2_IR,
    ST_EXIT1_IR,
    ST_SHIFT_IR,
    ST_PAUSE_IR,
    ST_RTI,
    ST_UPDATE_IR,
    ST_CAPTURE_IR,
    ST_TLR
    );
  
  type regs_t is
  record
    state : state_t;
  end record;

  signal r, rin: regs_t;
  
begin

  reg: process(tck_i)
  begin
    if rising_edge(tck_i) then
      r <= rin;
    end if;
  end process;

  transition: process(tms_i, trst_i, r)
  begin
    rin <= r;

    if trst_i = '0' then
      rin.state <= ST_TLR;
    elsif tms_i = '0' then
      case r.state is
        when ST_TLR => rin.state <= ST_RTI;
        when ST_RTI => rin.state <= ST_RTI;

        when ST_SELECT_DR  => rin.state <= ST_CAPTURE_DR;
        when ST_CAPTURE_DR => rin.state <= ST_SHIFT_DR;
        when ST_SHIFT_DR   => rin.state <= ST_SHIFT_DR;
        when ST_EXIT1_DR   => rin.state <= ST_PAUSE_DR;
        when ST_PAUSE_DR   => rin.state <= ST_PAUSE_DR;
        when ST_EXIT2_DR   => rin.state <= ST_SHIFT_DR;
        when ST_UPDATE_DR  => rin.state <= ST_RTI;

        when ST_SELECT_IR  => rin.state <= ST_CAPTURE_IR;
        when ST_CAPTURE_IR => rin.state <= ST_SHIFT_IR;
        when ST_SHIFT_IR   => rin.state <= ST_SHIFT_IR;
        when ST_EXIT1_IR   => rin.state <= ST_PAUSE_IR;
        when ST_PAUSE_IR   => rin.state <= ST_PAUSE_IR;
        when ST_EXIT2_IR   => rin.state <= ST_SHIFT_IR;
        when ST_UPDATE_IR  => rin.state <= ST_RTI;
      end case;
    else -- tms_i = '1'
      case r.state is
        when ST_TLR => rin.state <= ST_TLR;
        when ST_RTI => rin.state <= ST_SELECT_DR;

        when ST_SELECT_DR  => rin.state <= ST_SELECT_IR;
        when ST_CAPTURE_DR => rin.state <= ST_EXIT1_DR;
        when ST_SHIFT_DR   => rin.state <= ST_EXIT1_DR;
        when ST_EXIT1_DR   => rin.state <= ST_UPDATE_DR;
        when ST_PAUSE_DR   => rin.state <= ST_EXIT2_DR;
        when ST_EXIT2_DR   => rin.state <= ST_UPDATE_DR;
        when ST_UPDATE_DR  => rin.state <= ST_SELECT_DR;

        when ST_SELECT_IR  => rin.state <= ST_TLR;
        when ST_CAPTURE_IR => rin.state <= ST_EXIT1_IR;
        when ST_SHIFT_IR   => rin.state <= ST_EXIT1_IR;
        when ST_EXIT1_IR   => rin.state <= ST_UPDATE_IR;
        when ST_PAUSE_IR   => rin.state <= ST_EXIT2_IR;
        when ST_EXIT2_IR   => rin.state <= ST_UPDATE_IR;
        when ST_UPDATE_IR  => rin.state <= ST_SELECT_DR;
      end case;
    end if;
  end process;

  moore: process(r)
  begin
    reset_o      <= '0';
    run_o        <= '0';
    ir_capture_o <= '0';
    ir_shift_o   <= '0';
    ir_update_o  <= '0';
    dr_capture_o <= '0';
    dr_shift_o   <= '0';
    dr_update_o  <= '0';
    
    case r.state is
      when ST_TLR        => reset_o      <= '1';
      when ST_RTI        => run_o        <= '1';
      when ST_CAPTURE_DR => dr_capture_o <= '1';
      when ST_SHIFT_DR   => dr_shift_o   <= '1';
      when ST_UPDATE_DR  => dr_update_o  <= '1';
      when ST_CAPTURE_IR => ir_capture_o <= '1';
      when ST_SHIFT_IR   => ir_shift_o   <= '1';
      when ST_UPDATE_IR  => ir_update_o  <= '1';
      when others        => null;
    end case;
  end process;

end architecture;
