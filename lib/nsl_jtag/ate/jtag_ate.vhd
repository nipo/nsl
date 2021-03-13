library ieee;
use ieee.std_logic_1164.all;

library nsl_jtag, nsl_math;

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

  -- r.prescaler     543210------54321054321054321054321054
  --       ___________ ___________ ___________ ___________
  -- TMS   ___________X___________X___________X___________X 
  --            _____                   _____       _____
  -- TCK   ____/     \_________________/     \_____/     \ 
  --                ^ ^
  --                | |
  --                | \-- Decision taking for next cycle,
  --                |     retrieve commands, update outputs
  --                \-------- Gather TDO

  type tap_branch_t is (
    TAP_UNDEFINED,
    TAP_RESET,
    TAP_REG,
    TAP_RTI
    );

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_MOVING, -- shift TMS
    ST_SHIFT_PRE, -- Special kind of MOVING where next state is SHIFTING
    ST_SHIFTING,
    ST_SHIFT_PIPE_RSP,
    ST_SHIFT_PIPE_CMD,
    ST_SHIFT_POST,
    ST_SHIFT_DONE
    );

  constant tms_shreg_len : natural := 14;
  constant tms_move_max_len : natural := nsl_math.arith.max(14, data_max_size);

  type regs_t is
  record
    state : state_t;
    tap_branch : tap_branch_t;
    prescaler : natural range 0 to 2 ** prescaler_width - 1;
    data_shreg : std_ulogic_vector(data_max_size-1 downto 0);
    data_shreg_insertion_index, data_left : natural range 0 to data_max_size-1;
    tms_shreg : std_ulogic_vector(0 to tms_shreg_len-1);
    tms_left : natural range 0 to tms_move_max_len - 1 + 2;
    tck_shreg : std_ulogic_vector(0 to 1);
    pipeline_avaiable : boolean;
    tdo : std_ulogic;
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
      r.tck_shreg <= (others => '0');
      r.pipeline_avaiable <= false;
    end if;
  end process;

  transition: process(r, jtag_i, cmd_valid_i, cmd_op_i, cmd_data_i, cmd_size_m1_i, rsp_ready_i,
                      divisor_i)
    variable start : boolean;
  begin
    rin <= r;

    start := false;
    
    if r.tck_shreg /= (r.tck_shreg'range => '0') then
      if r.prescaler /= 0 then
        rin.prescaler <= r.prescaler - 1;
      else
        rin.prescaler <= divisor_i;
        rin.tck_shreg <= r.tck_shreg(1 to r.tck_shreg'right) & '0';

        if r.tck_shreg = "01" then -- rising edge
          rin.tdo <= jtag_i.tdo;
        end if;
      end if;
    else
      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if cmd_valid_i = '1' then
            case cmd_op_i is
              when nsl_jtag.ate.ATE_OP_RESET =>
                -- From state * to Reset
                rin.tms_shreg <= (others => '1');
                rin.tms_left <= 4;
                rin.tap_branch <= TAP_RESET;
                rin.state <= ST_MOVING;
                rin.prescaler <= divisor_i;
                start := true;

              when nsl_jtag.ate.ATE_OP_RTI =>
                case r.tap_branch is
                  when TAP_UNDEFINED =>
                    null;

                  when TAP_RESET | TAP_RTI =>
                    -- Stay
                    rin.tms_shreg <= (others => '0');
                    rin.tms_left <= cmd_size_m1_i;
                    rin.tap_branch <= TAP_RTI;
                    rin.state <= ST_MOVING;
                    start := true;

                  when TAP_REG =>
                    -- go through Exit2, Update to Rti
                    rin.tms_shreg <= (others => '0');
                    rin.tms_shreg(0 to 2) <= "110";
                    rin.tms_left <= cmd_size_m1_i + 2;
                    rin.tap_branch <= TAP_RTI;
                    rin.state <= ST_MOVING;
                    start := true;
                end case;

              when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET =>
                    null;

                  when TAP_RTI =>
                    -- Through Sel-DR, Capture, Exit1 to Pause
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 3) <= "1010";
                    rin.tms_left <= 3;
                    rin.tap_branch <= TAP_REG;
                    rin.state <= ST_MOVING;
                    start := true;

                  when TAP_REG =>
                    -- Loop through Exit2, Update, Sel-DR, Capture, Exit1 to Pause
                    -- Dont touch Rti
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 5) <= "111010";
                    rin.tms_left <= 5;
                    rin.tap_branch <= TAP_REG;
                    rin.state <= ST_MOVING;
                    start := true;
                end case;

              when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET =>
                    null;

                  when TAP_RTI =>
                    -- Through Sel-DR, Sel-IR, Capture, Exit1 to Pause
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 4) <= "11010";
                    rin.tms_left <= 4;
                    rin.tap_branch <= TAP_REG;
                    rin.state <= ST_MOVING;
                    start := true;

                  when TAP_REG =>
                    -- Loop through Exit2, Update, Sel-DR, Sel-IR, Capture, Exit1 to Pause
                    -- Dont touch Rti
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 6) <= "1111010";
                    rin.tms_left <= 6;
                    rin.tap_branch <= TAP_REG;
                    rin.state <= ST_MOVING;
                    start := true;
                end case;

              when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
                case r.tap_branch is
                  when TAP_UNDEFINED | TAP_RESET | TAP_RTI =>
                    rin.tms_shreg <= (others => '1');
                    rin.tms_shreg(0 to 12) <= "0011110011100";
                    rin.tms_left <= 13;
                    rin.tap_branch <= TAP_UNDEFINED;
                    rin.state <= ST_MOVING;
                    start := true;

                  when TAP_REG =>
                    null;
                end case;

              when nsl_jtag.ate.ATE_OP_SHIFT =>
                case r.tap_branch is
                  when TAP_REG =>
                    -- Through Exit2 to Shift
                    rin.tms_shreg <= (others => '-');
                    rin.tms_shreg(0 to 1) <= "10";
                    rin.tms_left <= 1;
                    rin.data_shreg <= cmd_data_i;
                    rin.data_left <= cmd_size_m1_i;
                    rin.data_shreg_insertion_index <= cmd_size_m1_i;
                    rin.tap_branch <= TAP_REG;
                    rin.state <= ST_SHIFT_PRE;
                    rin.pipeline_avaiable <= false;
                    start := true;

                  when others =>
                    -- This is an error, but still go though SHIFT_DONE in
                    -- order to unlock master waiting for TDO data
                    rin.state <= ST_SHIFT_DONE;
                end case;
            end case;
          end if;

        when ST_MOVING | ST_SHIFT_PRE | ST_SHIFT_POST =>
          if r.tms_left /= 0 then
            -- extend on right, on purpose
            rin.tms_shreg(0 to rin.tms_shreg'right-1) <= r.tms_shreg(1 to r.tms_shreg'right);
            rin.tms_left <= r.tms_left - 1;
            start := true;
          elsif r.state = ST_SHIFT_PRE then
            rin.state <= ST_SHIFTING;
            start := true;
          elsif r.state = ST_SHIFT_POST then
            rin.state <= ST_SHIFT_DONE;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_SHIFTING =>
          rin.data_shreg <= '-' & r.data_shreg(r.data_shreg'left downto 1);
          rin.data_shreg(r.data_shreg_insertion_index) <= r.tdo;
          start := true;
          if r.data_left = 0 then
            if allow_pipelining and r.pipeline_avaiable then
              rin.state <= ST_SHIFT_PIPE_RSP;
              start := false;
            else
              -- Last cycle was shifted with TMS=1, next cycle we are in Exit1.
              -- Now we need to go to Pause
              rin.tms_shreg <= (others => '-');
              rin.tms_shreg(0 to 0) <= "0";
              rin.tms_left <= 0;
              rin.state <= ST_SHIFT_POST;
            end if;
          else
            rin.data_left <= r.data_left - 1;
            case cmd_op_i is
              when nsl_jtag.ate.ATE_OP_SHIFT =>
                rin.pipeline_avaiable <= (rsp_ready_i = '1')
                                         and (cmd_valid_i = '1')
                                         and allow_pipelining;

              when others =>
                rin.pipeline_avaiable <= false;
            end case;
          end if;

        when ST_SHIFT_PIPE_RSP =>
          rin.state <= ST_SHIFT_PIPE_CMD;

        when ST_SHIFT_PIPE_CMD =>
          rin.data_shreg <= cmd_data_i;
          rin.data_left <= cmd_size_m1_i;
          rin.data_shreg_insertion_index <= cmd_size_m1_i;
          rin.state <= ST_SHIFTING;
          rin.pipeline_avaiable <= false;
          start := true;
          
        when ST_SHIFT_DONE =>
          if rsp_ready_i = '1' then
            rin.state <= ST_IDLE;
          end if;
      end case;
    end if;

    if start then
      rin.prescaler <= divisor_i;
      rin.tck_shreg <= "01";
    end if;
    
  end process;

  moore: process(r)
  begin
    cmd_ready_o <= '0';
    rsp_valid_o <= '0';
    jtag_o.tck <= r.tck_shreg(0);
    jtag_o.tdi <= r.data_shreg(0);
    jtag_o.tms <= r.tms_shreg(0);
    if r.tap_branch = TAP_RESET then
      jtag_o.trst <= '0';
    else
      jtag_o.trst <= '1';
    end if;

    rsp_data_o <= r.data_shreg;

    case r.state is
      when ST_IDLE | ST_SHIFT_PIPE_CMD =>
        cmd_ready_o <= '1';

      when ST_SHIFTING =>
        if r.data_left = 0 then
          if allow_pipelining and r.pipeline_avaiable then
            jtag_o.tms <= '0';
          else
            jtag_o.tms <= '1';
          end if;
        else
          jtag_o.tms <= '0';
        end if;

      when ST_SHIFT_DONE | ST_SHIFT_PIPE_RSP =>
        rsp_valid_o <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
