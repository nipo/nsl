library ieee;
use ieee.std_logic_1164.all;

library nsl_jtag, nsl_math, nsl_io, nsl_logic;
use nsl_io.io.all;
use nsl_logic.logic.all;

entity jtag_ate is
  generic (
    prescaler_width : positive;
    data_max_size : positive := 8;
    allow_pipelining : boolean := true
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    divisor_i  : in natural range 0 to 2 ** prescaler_width - 1 := 0;

    cmd_ready_o   : out std_ulogic;
    cmd_valid_i   : in  std_ulogic;
    cmd_op_i      : in  nsl_jtag.ate.ate_op;
    cmd_data_i    : in  std_ulogic_vector(data_max_size-1 downto 0);
    cmd_size_m1_i : in  natural range 0 to data_max_size-1;

    rsp_ready_i : in std_ulogic := '1';
    rsp_valid_o : out std_ulogic;
    rsp_data_o  : out std_ulogic_vector(data_max_size-1 downto 0);

    jtag_o : out nsl_jtag.jtag.jtag_ate_o;
    jtag_i : in nsl_jtag.jtag.jtag_ate_i
    );
end entity;

architecture rtl of jtag_ate is

  type tap_branch_t is (
    TAP_UNDEFINED,
    TAP_RESET,
    TAP_RTI,
    TAP_CAPTURED
    );

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_MOVE_LOW,
    ST_MOVE_HIGH,
    ST_SHIFT_LOW,
    ST_SHIFT_HIGH,
    -- Waiting for TDO to settle before sampling it and outputting
    -- data.
    ST_SHIFT_HOLD,
    ST_SHIFT_DONE
    );

  constant tms_shreg_len : natural := 14;
  constant tms_move_max_len : natural := nsl_math.arith.max(14, data_max_size);

  type regs_t is
  record
    state : state_t;
    tap_branch : tap_branch_t;
    prescaler : natural range 0 to 2 ** prescaler_width - 1;
    data_shreg, insertion_mask, insertion_val : std_ulogic_vector(data_max_size-1 downto 0);
    data_left : natural range 0 to data_max_size-1;
    tms_shreg : std_ulogic_vector(0 to tms_shreg_len-1);
    tms_left : natural range 0 to tms_move_max_len - 1 + 2;
    tdi, tdi_next : tristated;
  end record;

  signal r, rin: regs_t;

begin

  reg: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.prescaler <= 0;
    end if;
  end process;

  transition: process(r, jtag_i, cmd_valid_i, cmd_op_i, cmd_data_i, cmd_size_m1_i, rsp_ready_i,
                      divisor_i) is
  begin
    rin <= r;

    rin.insertion_val <= (others => jtag_i.tdo);
    
    if r.prescaler /= 0 then
      rin.prescaler <= r.prescaler - 1;
    else
      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.tdi_next <= tristated_z;
          rin.tdi <= tristated_z;

        when ST_IDLE =>
          if cmd_valid_i = '1' then
            case cmd_op_i is
              when nsl_jtag.ate.ATE_OP_RESET =>
                -- From state * to Reset
                rin.tms_shreg <= (others => '1');
                rin.tms_left <= cmd_size_m1_i;
                rin.tap_branch <= TAP_RESET;
                rin.state <= ST_MOVE_LOW;
                rin.prescaler <= divisor_i;

              when nsl_jtag.ate.ATE_OP_RTI =>
                case r.tap_branch is
                  when TAP_UNDEFINED =>
                    null;

                  when TAP_RESET | TAP_RTI =>
                    -- Stay
                    rin.tms_shreg <= (others => '0');
                    rin.tms_left <= cmd_size_m1_i;
                    rin.tap_branch <= TAP_RTI;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;

                  when TAP_CAPTURED =>
                    -- go through Exit1, Update to Rti
                    rin.tms_shreg <= (others => '0');
                    rin.tms_shreg(0 to 2) <= "110";
                    rin.tms_left <= cmd_size_m1_i + 2;
                    rin.tap_branch <= TAP_RTI;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;
                end case;

              when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET =>
                    null;

                  when TAP_RTI =>
                    -- Through Sel-DR, stay in Capture
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 1) <= "10";
                    rin.tms_left <= 1;
                    rin.tap_branch <= TAP_CAPTURED;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;

                  when TAP_CAPTURED =>
                    -- Loop through Exit1, Update, Sel-DR, Capture
                    -- Dont touch Rti
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 3) <= "1110";
                    rin.tms_left <= 3;
                    rin.tap_branch <= TAP_CAPTURED;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;
                end case;

              when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET =>
                    null;

                  when TAP_RTI =>
                    -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 2) <= "110";
                    rin.tms_left <= 2;
                    rin.tap_branch <= TAP_CAPTURED;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;

                  when TAP_CAPTURED =>
                    -- Loop through Exit1, Update, Sel-DR, Sel-IR, stay in Capture
                    -- Dont touch Rti
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 4) <= "11110";
                    rin.tms_left <= 4;
                    rin.tap_branch <= TAP_CAPTURED;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;
                end case;

              when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET =>
                    rin.tms_shreg <= (others => '1');
                    rin.tms_shreg(0 to 12) <= "0011110011100";
                    rin.tms_left <= 13;
                    rin.tap_branch <= TAP_UNDEFINED;
                    rin.state <= ST_MOVE_LOW;
                    rin.prescaler <= divisor_i;

                  when TAP_CAPTURED | TAP_RTI =>
                    null;
                end case;

              when nsl_jtag.ate.ATE_OP_SHIFT =>
                case r.tap_branch is
                  when TAP_CAPTURED =>
                    -- We are in Capture or ending Shift with
                    -- uncompleted cycle, we need to insert one TMS=0
                    -- cycle to go to next Shift cycle.
                    rin.data_shreg <= cmd_data_i;
                    rin.data_left <= cmd_size_m1_i;
                    rin.insertion_mask <= mask_range(data_max_size, cmd_size_m1_i, cmd_size_m1_i);
                    rin.tap_branch <= TAP_CAPTURED;
                    rin.state <= ST_SHIFT_LOW;
                    rin.prescaler <= divisor_i;

                  when others =>
                    -- This is an error, but still go though SHIFT_DONE in
                    -- order to unlock master waiting for TDO data
                    rin.state <= ST_SHIFT_DONE;
                end case;
            end case;
          end if;

        when ST_MOVE_LOW =>
          rin.state <= ST_MOVE_HIGH;
          rin.prescaler <= divisor_i;
          rin.tdi_next <= tristated_z;
          
        when ST_MOVE_HIGH =>
          rin.tdi <= r.tdi_next;
          if r.tms_left /= 0 then
            -- extend on right, on purpose
            rin.tms_shreg(0 to rin.tms_shreg'right-1) <= r.tms_shreg(1 to r.tms_shreg'right);
            rin.tms_left <= r.tms_left - 1;
            rin.prescaler <= divisor_i;
            rin.state <= ST_MOVE_LOW;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_SHIFT_LOW =>
          rin.data_shreg <= mask_merge(
            '0' & r.data_shreg(r.data_shreg'left downto 1),
            r.insertion_val,
            r.insertion_mask);
          rin.tdi_next <= to_tristated(r.data_shreg(0));
          rin.state <= ST_SHIFT_HIGH;
          rin.prescaler <= divisor_i;

        when ST_SHIFT_HIGH =>
          rin.tdi <= r.tdi_next;
          if r.data_left /= 0 then
            rin.state <= ST_SHIFT_LOW;
            rin.data_left <= r.data_left - 1;
          else
            rin.state <= ST_SHIFT_HOLD;
          end if;
          rin.prescaler <= divisor_i;

        when ST_SHIFT_HOLD =>
          rin.data_shreg <= mask_merge(
            '0' & r.data_shreg(r.data_shreg'left downto 1),
            r.insertion_val,
            r.insertion_mask);
          rin.tdi_next <= to_tristated(r.data_shreg(0));
          rin.state <= ST_SHIFT_DONE;
          
        when ST_SHIFT_DONE =>
          if rsp_ready_i = '1' then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end if;
  end process;

  moore: process(r)
  begin
    jtag_o.trst <= '1';
    jtag_o.tdi <= r.tdi;
    jtag_o.tck <= '0';
    jtag_o.tms <= r.tms_shreg(0);

    case r.state is
      when ST_SHIFT_HIGH | ST_MOVE_HIGH =>
        jtag_o.tck <= '1';

      when others =>
        null;
    end case;

    case r.state is
      when ST_MOVE_LOW | ST_MOVE_HIGH =>
        if r.tms_shreg(0 to 4) = "11111"
          and r.tms_left >= 4 then
          jtag_o.trst <= '0';
        end if;

      when ST_SHIFT_HIGH | ST_SHIFT_HOLD | ST_SHIFT_LOW =>
        jtag_o.tms <= '0';

      when others =>
        null;
    end case;

    cmd_ready_o <= '0';
    rsp_valid_o <= '0';
    rsp_data_o <= r.data_shreg;
    case r.state is
      when ST_IDLE =>
        cmd_ready_o <= '1';

      when ST_SHIFT_DONE =>
        rsp_valid_o <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
