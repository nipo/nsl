library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_math, nsl_io, nsl_logic, nsl_event;
use nsl_io.io.all;
use nsl_logic.logic.all;
use nsl_event.tick.all;

entity jtag_ate is
  generic (
    data_max_size : positive := 8;
    delay_max_l2_c : positive := 3;
    allow_pipelining : boolean := true
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    tick_i : in std_ulogic;

    cmd_ready_o   : out std_ulogic;
    cmd_valid_i   : in  std_ulogic;
    cmd_op_i      : in  nsl_jtag.ate.ate_op;
    cmd_data_i    : in  std_ulogic_vector(data_max_size-1 downto 0);
    cmd_size_m1_i : in  natural range 0 to data_max_size-1;

    rsp_ready_i : in std_ulogic := '1';
    rsp_valid_o : out std_ulogic;
    rsp_data_o  : out std_ulogic_vector(data_max_size-1 downto 0);

    tick_delay_i : in unsigned(delay_max_l2_c-1 downto 0);

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

  type state_input_t is (
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

    type state_output_t is (
    ST_RESET,
    ST_IDLE,
    ST_SHIFT_LOW,
    ST_SHIFT_HIGH,
    -- Waiting for TDO to settle before sampling it and outputting
    -- data.
    ST_SHIFT_HOLD,
    ST_SHIFT_DONE
    );
  
  constant tms_shreg_len : natural := 14;
  constant tms_move_max_len : natural := nsl_math.arith.max(14, data_max_size);

  type regs_in_t is
  record
    state : state_input_t;
    tap_branch : tap_branch_t;
    data_shreg, insertion_mask : std_ulogic_vector(data_max_size-1 downto 0);
    data_left : natural range 0 to data_max_size-1;
    tms_shreg : std_ulogic_vector(0 to tms_shreg_len-1);
    tms_left : natural range 0 to tms_move_max_len - 1 + 2;
    tdi, tdi_next : tristated;
  end record;

  type regs_out_t is
  record
    state : state_output_t;
    tap_branch : tap_branch_t;
    data_shreg, insertion_mask, insertion_val : std_ulogic_vector(data_max_size-1 downto 0);
    data_left : natural range 0 to data_max_size-1;    
  end record;

  signal r_input, rin_input: regs_in_t;
  signal r_output, rin_output: regs_out_t;

  signal s_cmd_ready: std_ulogic;
  signal s_rsp_valid: std_ulogic;
  signal s_delayed_tick: std_ulogic;
  signal s_tick_i: std_ulogic;
  signal s_tick_n_rst: std_ulogic;

begin

  -- Output ports tied to internal signals
  cmd_ready_o <= s_cmd_ready;
  rsp_valid_o <= s_rsp_valid;

  reg_tdi: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r_input <= rin_input;
    end if;

    if reset_n_i = '0' then
      r_input.state <= ST_RESET;
    end if;
  end process;

  transition_tdi: process(cmd_data_i, cmd_op_i, cmd_size_m1_i, cmd_valid_i,
                          r_input, rsp_ready_i, s_rsp_valid, tick_i) is
  begin
    rin_input <= r_input;

    case r_input.state is
      when ST_RESET =>
        rin_input.state <= ST_IDLE;
        rin_input.tdi_next <= tristated_z;
        rin_input.tdi <= tristated_z;

      when ST_IDLE =>
        if cmd_valid_i = '1' then
          case cmd_op_i is
            when nsl_jtag.ate.ATE_OP_RESET =>
              -- From state * to Reset
              rin_input.tms_shreg <= (others => '1');
              rin_input.tms_left <= cmd_size_m1_i;
              rin_input.tap_branch <= TAP_RESET;
              rin_input.state <= ST_MOVE_LOW;

            when nsl_jtag.ate.ATE_OP_RTI =>
              case r_input.tap_branch is
                when TAP_UNDEFINED =>
                  null;

                when TAP_RESET | TAP_RTI =>
                  -- Stay
                  rin_input.tms_shreg <= (others => '0');
                  rin_input.tms_left <= cmd_size_m1_i;
                  rin_input.tap_branch <= TAP_RTI;
                  rin_input.state <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- go through Exit1, Update to Rti
                  rin_input.tms_shreg <= (others => '0');
                  rin_input.tms_shreg(0 to 2) <= "110";
                  rin_input.tms_left <= cmd_size_m1_i + 2;
                  rin_input.tap_branch <= TAP_RTI;
                  rin_input.state <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
              case r_input.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, stay in Capture
                  rin_input.tms_shreg <= (others => '-');
                  rin_input.tms_shreg(0 to 1) <= "10";
                  rin_input.tms_left <= 1;
                  rin_input.tap_branch <= TAP_CAPTURED;
                  rin_input.state <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Capture
                  -- Dont touch Rti
                  rin_input.tms_shreg <= (others => '-');
                  rin_input.tms_shreg(0 to 3) <= "1110";
                  rin_input.tms_left <= 3;
                  rin_input.tap_branch <= TAP_CAPTURED;
                  rin_input.state <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
              case r_input.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                  rin_input.tms_shreg <= (others => '-');
                  rin_input.tms_shreg(0 to 2) <= "110";
                  rin_input.tms_left <= 2;
                  rin_input.tap_branch <= TAP_CAPTURED;
                  rin_input.state <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Sel-IR, stay in Capture
                  -- Dont touch Rti
                  rin_input.tms_shreg <= (others => '-');
                  rin_input.tms_shreg(0 to 4) <= "11110";
                  rin_input.tms_left <= 4;
                  rin_input.tap_branch <= TAP_CAPTURED;
                  rin_input.state <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
              case r_input.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  rin_input.tms_shreg <= (others => '1');
                  rin_input.tms_shreg(0 to 12) <= "0011110011100";
                  rin_input.tms_left <= 13;
                  rin_input.tap_branch <= TAP_UNDEFINED;
                  rin_input.state <= ST_MOVE_LOW;

                when TAP_CAPTURED | TAP_RTI =>
                  null;
              end case;

            when nsl_jtag.ate.ATE_OP_SHIFT =>
              case r_input.tap_branch is
                when TAP_CAPTURED =>
                  -- We are in Capture or ending Shift with
                  -- uncompleted cycle, we need to insert one TMS=0
                  -- cycle to go to next Shift cycle.
                  rin_input.data_shreg <= cmd_data_i;
                  rin_input.data_left <= cmd_size_m1_i;
                  rin_input.insertion_mask <= mask_range(data_max_size, cmd_size_m1_i, cmd_size_m1_i);
                  rin_input.tap_branch <= TAP_CAPTURED;
                  rin_input.state <= ST_SHIFT_LOW;

                when others =>
                  -- This is an error, but still go though SHIFT_DONE in
                  -- order to unlock master waiting for TDO data
                  rin_input.state <= ST_SHIFT_DONE;
              end case;
          end case;
        end if;

      when ST_MOVE_LOW =>
        if tick_i = '1' then
          rin_input.state <= ST_MOVE_HIGH;
          rin_input.tdi_next <= tristated_z;
        end if;
        
      when ST_MOVE_HIGH =>
        if tick_i = '1' then
          rin_input.tdi <= r_input.tdi_next;
          if r_input.tms_left /= 0 then
            -- extend on right, on purpose
            rin_input.tms_shreg(0 to rin_input.tms_shreg'right-1) <= r_input.tms_shreg(1 to r_input.tms_shreg'right);
            rin_input.tms_left <= r_input.tms_left - 1;
            rin_input.state <= ST_MOVE_LOW;
          else
            rin_input.state <= ST_IDLE;
          end if;
        end if;

      when ST_SHIFT_LOW =>
        if tick_i = '1' then
          rin_input.data_shreg <= mask_merge(
            '0' & r_input.data_shreg(r_input.data_shreg'left downto 1),
            "--------",
            r_input.insertion_mask);
          rin_input.tdi_next <= to_tristated(r_input.data_shreg(0));
          rin_input.state <= ST_SHIFT_HIGH;
        end if;

      when ST_SHIFT_HIGH =>
        if tick_i = '1' then
          rin_input.tdi <= r_input.tdi_next;
          if r_input.data_left /= 0 then
            rin_input.state <= ST_SHIFT_LOW;
            rin_input.data_left <= r_input.data_left - 1;
          else
            rin_input.state <= ST_SHIFT_HOLD;
          end if;
        end if;

      when ST_SHIFT_HOLD =>
        if tick_i = '1' then
          rin_input.data_shreg <= mask_merge(
            '0' & r_input.data_shreg(r_input.data_shreg'left downto 1),
            "--------",
            r_input.insertion_mask);          
          rin_input.tdi_next <= to_tristated(r_input.data_shreg(0));
          rin_input.state <= ST_SHIFT_DONE;
        end if;

      when ST_SHIFT_DONE =>
        if (rsp_ready_i = '1') and (s_rsp_valid = '1') then
          rin_input.state <= ST_IDLE;
        end if;        
    end case;
  end process;

  reg_tdo: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r_output <= rin_output;
    end if;

    if reset_n_i = '0' then
      r_output.state <= ST_RESET;
    end if;
  end process;

  transition_tdo: process(cmd_op_i, cmd_size_m1_i, cmd_valid_i, jtag_i.tdo,
                          r_output, rsp_ready_i, s_cmd_ready, s_delayed_tick,
                          s_rsp_valid) is
  begin
    rin_output <= r_output;

    rin_output.insertion_val <= (others => jtag_i.tdo);
    
    case r_output.state is
      when ST_RESET =>
        rin_output.state <= ST_IDLE;

      when ST_IDLE =>
        if (cmd_valid_i = '1') and (s_cmd_ready = '1') then
          case cmd_op_i is
            when nsl_jtag.ate.ATE_OP_RESET =>
              -- From state * to Reset
              rin_output.tap_branch <= TAP_RESET;

            when nsl_jtag.ate.ATE_OP_RTI =>
              case r_output.tap_branch is
                when TAP_UNDEFINED =>
                  null;

                when TAP_RESET | TAP_RTI =>
                  -- Stay
                  rin_output.tap_branch <= TAP_RTI;

                when TAP_CAPTURED =>
                  -- go through Exit1, Update to Rti
                  rin_output.tap_branch <= TAP_RTI;
              end case;

            when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
              case r_output.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, stay in Capture
                  rin_output.tap_branch <= TAP_CAPTURED;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Capture
                  -- Dont touch Rti
                  rin_output.tap_branch <= TAP_CAPTURED;
              end case;

            when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
              case r_output.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                  rin_output.tap_branch <= TAP_CAPTURED;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Sel-IR, stay in Capture
                  -- Dont touch Rti
                  rin_output.tap_branch <= TAP_CAPTURED;
              end case;

            when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
              case r_output.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  rin_output.tap_branch <= TAP_UNDEFINED;

                when TAP_CAPTURED | TAP_RTI =>
                  null;
              end case;

            when nsl_jtag.ate.ATE_OP_SHIFT =>
              case r_output.tap_branch is
                when TAP_CAPTURED =>
                  -- We are in Capture or ending Shift with
                  -- uncompleted cycle, we need to insert one TMS=0
                  -- cycle to go to next Shift cycle.
                  rin_output.data_shreg <= (others => '-');
                  rin_output.data_left <= cmd_size_m1_i;
                  rin_output.insertion_mask <= mask_range(data_max_size, cmd_size_m1_i, cmd_size_m1_i);
                  rin_output.tap_branch <= TAP_CAPTURED;
                  rin_output.state <= ST_SHIFT_LOW;

                when others =>
                  -- This is an error, but still go though SHIFT_DONE in
                  -- order to unlock master waiting for TDO data
                  rin_output.state <= ST_SHIFT_DONE;
              end case;
          end case;
        end if;

      when ST_SHIFT_LOW =>
        if s_delayed_tick = '1' then
          rin_output.data_shreg <= mask_merge(
            '0' & r_output.data_shreg(r_output.data_shreg'left downto 1),
            r_output.insertion_val,
            r_output.insertion_mask);
          rin_output.state <= ST_SHIFT_HIGH;
        end if;

      when ST_SHIFT_HIGH =>
        if s_delayed_tick = '1' then
          if r_output.data_left /= 0 then
            rin_output.state <= ST_SHIFT_LOW;
            rin_output.data_left <= r_output.data_left - 1;
          else
            rin_output.state <= ST_SHIFT_HOLD;
          end if;
        end if;

      when ST_SHIFT_HOLD =>
        if s_delayed_tick = '1' then
          rin_output.data_shreg <= mask_merge(
            '0' & r_output.data_shreg(r_output.data_shreg'left downto 1),
            r_output.insertion_val,
            r_output.insertion_mask);
          rin_output.state <= ST_SHIFT_DONE;
        end if;
        
      when ST_SHIFT_DONE =>
        if (rsp_ready_i = '1') and (s_rsp_valid = '1') then
          rin_output.state <= ST_IDLE;
        end if;
    end case;
  end process;  

  ready_valid: process (r_input, r_output) is
  begin  -- process ready_valid

    s_cmd_ready <= '0';
    s_rsp_valid <= '0';

    rsp_data_o <= r_output.data_shreg;    
    
    if (r_input.state = ST_IDLE) and (r_output.state = ST_IDLE) then
      s_cmd_ready <= '1';
    end if;
    
    if (r_input.state = ST_SHIFT_DONE) and (r_output.state = ST_SHIFT_DONE) then
      s_rsp_valid <= '1';
    end if;    
  end process ready_valid;
  
  moore: process(r_input)
  begin
    jtag_o.trst <= '1';
    jtag_o.tdi <= r_input.tdi;
    jtag_o.tck <= '0';
    jtag_o.tms <= r_input.tms_shreg(0);

    case r_input.state is
      when ST_SHIFT_HIGH | ST_MOVE_HIGH =>
        jtag_o.tck <= '1';

      when others =>
        null;
    end case;

    case r_input.state is
      when ST_MOVE_LOW | ST_MOVE_HIGH =>
        if r_input.tms_shreg(0 to 4) = "11111"
          and r_input.tms_left >= 4 then
          jtag_o.trst <= '0';
        end if;

      when ST_SHIFT_HIGH | ST_SHIFT_HOLD | ST_SHIFT_LOW =>
        jtag_o.tms <= '0';

      when others =>
        null;
    end case;

  end process;

  tick_delay_in: process (r_input.state, tick_i) is
  begin  -- process tick_delay_in
    case r_input.state is
      when ST_SHIFT_LOW | ST_SHIFT_HIGH | ST_SHIFT_HOLD | ST_SHIFT_DONE =>
        s_tick_i <= tick_i;
        s_tick_n_rst <= '1';
      when others =>
        s_tick_i <= '0';
        s_tick_n_rst <= '0';
    end case;
  end process tick_delay_in;

  -- Tick variable delay instantiation
  tick_variable_delay_1: tick_variable_delay
    generic map (
      delay_max_l2_c => delay_max_l2_c)
    port map (
      clock_i   => clock_i,
      reset_n_i => s_tick_n_rst,
      tick_i    => s_tick_i,
      tick_o    => s_delayed_tick,
      delay_i   => tick_delay_i);

end architecture;
