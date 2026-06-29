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
    delay_max_l2_c : natural := 0;
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

    tick_delay_i : in unsigned(delay_max_l2_c-1 downto 0) := (others => '0');

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
  constant dont_care_vector : std_ulogic_vector(data_max_size-1 downto 0) := (others => '-');

  type regs_t is
  record
    state_in : state_input_t;
    state_out : state_output_t;
    tap_branch_in, tap_branch_out : tap_branch_t;
    data_shreg_in, data_shreg_out: std_ulogic_vector(data_max_size-1 downto 0);
    insertion_mask_in, insertion_mask_out : std_ulogic_vector(data_max_size-1 downto 0);
    insertion_val : std_ulogic_vector(data_max_size-1 downto 0);
    data_left_in, data_left_out : natural range 0 to data_max_size-1;
    tms_shreg : std_ulogic_vector(0 to tms_shreg_len-1);
    tms_left : natural range 0 to tms_move_max_len - 1 + 2;
    tdi, tdi_next : tristated;
  end record;

  signal r, rin: regs_t;

  signal s_cmd_ready: std_ulogic;
  signal s_rsp_valid: std_ulogic;
  signal s_delayed_tick: std_ulogic;
  signal s_tick_i: std_ulogic;
  signal s_tick_n_rst: std_ulogic;

begin

  -- Output ports tied to internal signals
  cmd_ready_o <= s_cmd_ready;
  rsp_valid_o <= s_rsp_valid;

  reg: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state_in <= ST_RESET;
      r.state_out <= ST_RESET;
    end if;
  end process;

  transition_tdi: process(cmd_data_i, cmd_op_i, cmd_size_m1_i, cmd_valid_i,
                          jtag_i.tdo, r, rsp_ready_i, s_cmd_ready,
                          s_delayed_tick, s_rsp_valid, tick_i) is
  begin

    -- First state machine
    rin <= r;

    case r.state_in is
      when ST_RESET =>
        rin.state_in <= ST_IDLE;
        rin.tdi_next <= tristated_z;
        rin.tdi <= tristated_z;

      when ST_IDLE =>
        if cmd_valid_i = '1' then
          case cmd_op_i is
            when nsl_jtag.ate.ATE_OP_RESET =>
              -- From state * to Reset
              rin.tms_shreg <= (others => '1');
              rin.tms_left <= cmd_size_m1_i;
              rin.tap_branch_in <= TAP_RESET;
              rin.state_in <= ST_MOVE_LOW;

            when nsl_jtag.ate.ATE_OP_RTI =>
              case r.tap_branch_in is
                when TAP_UNDEFINED =>
                  null;

                when TAP_RESET | TAP_RTI =>
                  -- Stay
                  rin.tms_shreg <= (others => '0');
                  rin.tms_left <= cmd_size_m1_i;
                  rin.tap_branch_in <= TAP_RTI;
                  rin.state_in <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- go through Exit1, Update to Rti
                  rin.tms_shreg <= (others => '0');
                  rin.tms_shreg(0 to 2) <= "110";
                  rin.tms_left <= cmd_size_m1_i + 2;
                  rin.tap_branch_in <= TAP_RTI;
                  rin.state_in <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
              case r.tap_branch_in is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, stay in Capture
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 1) <= "10";
                  rin.tms_left <= 1;
                  rin.tap_branch_in <= TAP_CAPTURED;
                  rin.state_in <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Capture
                  -- Dont touch Rti
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 3) <= "1110";
                  rin.tms_left <= 3;
                  rin.tap_branch_in <= TAP_CAPTURED;
                  rin.state_in <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
              case r.tap_branch_in is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 2) <= "110";
                  rin.tms_left <= 2;
                  rin.tap_branch_in <= TAP_CAPTURED;
                  rin.state_in <= ST_MOVE_LOW;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Sel-IR, stay in Capture
                  -- Dont touch Rti
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 4) <= "11110";
                  rin.tms_left <= 4;
                  rin.tap_branch_in <= TAP_CAPTURED;
                  rin.state_in <= ST_MOVE_LOW;
              end case;

            when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
              case r.tap_branch_in is
                when TAP_UNDEFINED | TAP_RESET =>
                  rin.tms_shreg <= (others => '1');
                  rin.tms_shreg(0 to 12) <= "0011110011100";
                  rin.tms_left <= 13;
                  rin.tap_branch_in <= TAP_UNDEFINED;
                  rin.state_in <= ST_MOVE_LOW;

                when TAP_CAPTURED | TAP_RTI =>
                  null;
              end case;

            when nsl_jtag.ate.ATE_OP_SHIFT =>
              case r.tap_branch_in is
                when TAP_CAPTURED =>
                  -- We are in Capture or ending Shift with
                  -- uncompleted cycle, we need to insert one TMS=0
                  -- cycle to go to next Shift cycle.
                  rin.data_shreg_in <= cmd_data_i;
                  rin.data_left_in <= cmd_size_m1_i;
                  rin.insertion_mask_in <= mask_range(data_max_size, cmd_size_m1_i, cmd_size_m1_i);
                  rin.tap_branch_in <= TAP_CAPTURED;
                  rin.state_in <= ST_SHIFT_LOW;

                when others =>
                  -- This is an error, but still go though SHIFT_DONE in
                  -- order to unlock master waiting for TDO data
                  rin.state_in <= ST_SHIFT_DONE;
              end case;
          end case;
        end if;

      when ST_MOVE_LOW =>
        if tick_i = '1' then
          rin.state_in <= ST_MOVE_HIGH;
          rin.tdi_next <= tristated_z;
        end if;
        
      when ST_MOVE_HIGH =>
        if tick_i = '1' then
          rin.tdi <= r.tdi_next;
          if r.tms_left /= 0 then
            -- extend on right, on purpose
            rin.tms_shreg(0 to rin.tms_shreg'right-1) <= r.tms_shreg(1 to r.tms_shreg'right);
            rin.tms_left <= r.tms_left - 1;
            rin.state_in <= ST_MOVE_LOW;
          else
            rin.state_in <= ST_IDLE;
          end if;
        end if;

      when ST_SHIFT_LOW =>
        if tick_i = '1' then
          rin.data_shreg_in <= mask_merge(
            '0' & r.data_shreg_in(r.data_shreg_in'left downto 1),
            dont_care_vector,
            r.insertion_mask_in);
          rin.tdi_next <= to_tristated(r.data_shreg_in(0));
          rin.state_in <= ST_SHIFT_HIGH;
        end if;

      when ST_SHIFT_HIGH =>
        if tick_i = '1' then
          rin.tdi <= r.tdi_next;
          if r.data_left_in /= 0 then
            rin.state_in <= ST_SHIFT_LOW;
            rin.data_left_in <= r.data_left_in - 1;
          else
            rin.state_in <= ST_SHIFT_HOLD;
          end if;
        end if;

      when ST_SHIFT_HOLD =>
        if tick_i = '1' then
          rin.data_shreg_in <= mask_merge(
            '0' & r.data_shreg_in(r.data_shreg_in'left downto 1),
            dont_care_vector,
            r.insertion_mask_in);          
          rin.tdi_next <= to_tristated(r.data_shreg_in(0));
          rin.state_in <= ST_SHIFT_DONE;
        end if;

      when ST_SHIFT_DONE =>
        if (rsp_ready_i = '1') and (s_rsp_valid = '1') then
          rin.state_in <= ST_IDLE;
        end if;        
    end case;

    -- Second state machine

    rin.insertion_val <= (others => jtag_i.tdo);
    
    case r.state_out is
      when ST_RESET =>
        rin.state_out <= ST_IDLE;

      when ST_IDLE =>
        if (cmd_valid_i = '1') and (s_cmd_ready = '1') then
          case cmd_op_i is
            when nsl_jtag.ate.ATE_OP_RESET =>
              -- From state_out * to Reset
              rin.tap_branch_out <= TAP_RESET;

            when nsl_jtag.ate.ATE_OP_RTI =>
              case r.tap_branch_out is
                when TAP_UNDEFINED =>
                  null;

                when TAP_RESET | TAP_RTI =>
                  -- Stay
                  rin.tap_branch_out <= TAP_RTI;

                when TAP_CAPTURED =>
                  -- go through Exit1, Update to Rti
                  rin.tap_branch_out <= TAP_RTI;
              end case;

            when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
              case r.tap_branch_out is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, stay in Capture
                  rin.tap_branch_out <= TAP_CAPTURED;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Capture
                  -- Dont touch Rti
                  rin.tap_branch_out <= TAP_CAPTURED;
              end case;

            when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
              case r.tap_branch_out is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;

                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                  rin.tap_branch_out <= TAP_CAPTURED;

                when TAP_CAPTURED =>
                  -- Loop through Exit1, Update, Sel-DR, Sel-IR, stay in Capture
                  -- Dont touch Rti
                  rin.tap_branch_out <= TAP_CAPTURED;
              end case;

            when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
              case r.tap_branch_out is
                when TAP_UNDEFINED | TAP_RESET =>
                  rin.tap_branch_out <= TAP_UNDEFINED;

                when TAP_CAPTURED | TAP_RTI =>
                  null;
              end case;

            when nsl_jtag.ate.ATE_OP_SHIFT =>
              case r.tap_branch_out is
                when TAP_CAPTURED =>
                  -- We are in Capture or ending Shift with
                  -- uncompleted cycle, we need to insert one TMS=0
                  -- cycle to go to next Shift cycle.
                  rin.data_shreg_out <= (others => '-');
                  rin.data_left_out <= cmd_size_m1_i;
                  rin.insertion_mask_out <= mask_range(data_max_size, cmd_size_m1_i, cmd_size_m1_i);
                  rin.tap_branch_out <= TAP_CAPTURED;
                  rin.state_out <= ST_SHIFT_LOW;

                when others =>
                  -- This is an error, but still go though SHIFT_DONE in
                  -- order to unlock master waiting for TDO data
                  rin.state_out <= ST_SHIFT_DONE;
              end case;
          end case;
        end if;

      when ST_SHIFT_LOW =>
        if s_delayed_tick = '1' then
          rin.data_shreg_out <= mask_merge(
            '0' & r.data_shreg_out(r.data_shreg_out'left downto 1),
            r.insertion_val,
            r.insertion_mask_out);
          rin.state_out <= ST_SHIFT_HIGH;
        end if;

      when ST_SHIFT_HIGH =>
        if s_delayed_tick = '1' then
          if r.data_left_out /= 0 then
            rin.state_out <= ST_SHIFT_LOW;
            rin.data_left_out <= r.data_left_out - 1;
          else
            rin.state_out <= ST_SHIFT_HOLD;
          end if;
        end if;

      when ST_SHIFT_HOLD =>
        if s_delayed_tick = '1' then
          rin.data_shreg_out <= mask_merge(
            '0' & r.data_shreg_out(r.data_shreg_out'left downto 1),
            r.insertion_val,
            r.insertion_mask_out);
          rin.state_out <= ST_SHIFT_DONE;
        end if;
        
      when ST_SHIFT_DONE =>
        if (rsp_ready_i = '1') and (s_rsp_valid = '1') then
          rin.state_out <= ST_IDLE;
        end if;
    end case;    
  end process;

  ready_valid: process (r) is
  begin  -- process ready_valid

    s_cmd_ready <= '0';
    s_rsp_valid <= '0';

    rsp_data_o <= r.data_shreg_out;    
    
    if (r.state_in = ST_IDLE) and (r.state_out = ST_IDLE) then
      s_cmd_ready <= '1';
    end if;
    
    if (r.state_in = ST_SHIFT_DONE) and (r.state_out = ST_SHIFT_DONE) then
      s_rsp_valid <= '1';
    end if;    
  end process ready_valid;
  
  moore: process(r)
  begin
    jtag_o.trst <= '1';
    jtag_o.tdi <= r.tdi;
    jtag_o.tck <= '0';
    jtag_o.tms <= r.tms_shreg(0);

    case r.state_in is
      when ST_SHIFT_HIGH | ST_MOVE_HIGH =>
        jtag_o.tck <= '1';

      when others =>
        null;
    end case;

    case r.state_in is
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

  end process;

  tick_delay_in: process (r.state_in, tick_i) is
  begin  -- process tick_delay_in
    case r.state_in is
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
