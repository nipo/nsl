library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.jtag.all;

entity jtag_sim_tap is
  generic(
    idcode_c : std_ulogic_vector(31 downto 0);
    idcode_instruction_c : std_ulogic_vector;
    user0_instruction_c : std_ulogic_vector
    );
  port(
    tck_i  : in  std_ulogic;
    tms_i  : in  std_ulogic;
    tdi_i  : in  std_ulogic;
    tdo_o  : out std_ulogic
    );
end entity;

architecture beh of jtag_sim_tap is

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
    ir, ir_shreg: std_ulogic_vector(idcode_instruction_c'length - 1 downto 0);
    bypass_shreg: std_ulogic_vector(0 downto 0);
    idcode_shreg: std_ulogic_vector(31 downto 0);
  end record;

  signal r, rin: regs_t;

  signal ir_capture_s : std_ulogic;
  signal ir_shift_s   : std_ulogic;
  signal ir_update_s  : std_ulogic;

begin

  reg: process(tck_i)
  begin
    if rising_edge(tck_i) then
      r <= rin;
    end if;
  end process;

  transition: process(tms_i, tdi_i, r)
  begin
    rin <= r;

    if tms_i = '0' then
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

    case r.state is
      when ST_TLR =>
        rin.ir <= idcode_instruction_c;

      when ST_CAPTURE_IR =>
        rin.ir_shreg <= (others => '0');
        rin.ir_shreg(0) <= '1';

      when ST_SHIFT_IR =>
        rin.ir_shreg <= tdi_i & r.ir_shreg(r.ir_shreg'left downto 1);

      when ST_UPDATE_IR =>
        rin.ir <= r.ir_shreg;

      when ST_CAPTURE_DR =>
        if r.ir = idcode_instruction_c then
          rin.idcode_shreg <= idcode_c;
        else
          rin.bypass_shreg <= (others => '0');
        end if;

      when ST_SHIFT_DR =>
          if r.ir = idcode_instruction_c then
            rin.idcode_shreg <= tdi_i & r.idcode_shreg(r.idcode_shreg'left downto 1);
          else
            rin.bypass_shreg <= tdi_i & r.bypass_shreg(r.bypass_shreg'left downto 1);
          end if;

      when others =>
        null;
    end case;
  end process;

  tck_g <= tck_i;
  tdi_g <= tdi_i;

  outputs: process(r, reg_tdo_g) is
    variable ir_int, ir_user0_int : integer;
  begin
    tlr_g <= '0';
    rti_g <= '0';
    dr_capture_g <= '0';
    dr_shift_g <= '0';
    dr_update_g <= '0';
    tdo_o <= 'Z';

    ir_int := to_integer(unsigned(r.ir));
    ir_user0_int := to_integer(unsigned(user0_instruction_c));

    case r.state is
      when ST_TLR =>
        tlr_g <= '1';

      when ST_RTI =>
        rti_g <= '1';

      when ST_CAPTURE_DR =>
        dr_capture_g <= '1';

      when ST_SHIFT_DR =>
        dr_shift_g <= '1';
        if r.ir = (r.ir'range => '1') then
          tdo_o <= r.bypass_shreg(0);
        elsif r.ir = idcode_instruction_c then
          tdo_o <= r.idcode_shreg(0);
        elsif ir_int >= ir_user0_int and ir_int < ir_user0_int + max_reg_count_c then
          tdo_o <= reg_tdo_g(ir_int - ir_user0_int);
        else
          tdo_o <= r.bypass_shreg(0);
        end if;
      when ST_SHIFT_IR =>
        tdo_o <= r.ir_shreg(0);

      when ST_UPDATE_DR =>
        dr_update_g <= '1';

      when others =>
        null;
    end case;

    if ir_int >= ir_user0_int and ir_int < ir_user0_int + max_reg_count_c then
      reg_sel_g <= ir_int - ir_user0_int;
    else
      reg_sel_g <= -1;
    end if;
  end process;

end architecture;
