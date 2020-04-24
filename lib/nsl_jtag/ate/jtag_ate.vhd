library ieee;
use ieee.std_logic_1164.all;

library nsl_jtag;

entity jtag_ate is
  generic (
    prescaler_width : positive;
    data_max_size : positive := 8
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

  -- r.prescaler     54321054321054321054321054321054321054
  -- r.tck           00000011111100000011111100000011111100
  -- rising               1           1           1
  -- falling                    1           1           1
  --             ____        ____        ____        ____
  -- TCK        /    \      /    \      /    \      /    \
  --       ____/      \____/      \____/      \____/      \
  --                      ^     ^
  --                      |     |
  --                      |     \-- Decision taking for next cycle,
  --                      |         retrieve commands, update outputs
  --                      \-------- Gather TDO

  type tap_branch_t is (
    TAP_UNDEFINED,
    TAP_REG,
    TAP_RESET,
    TAP_RTI
    );

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_MOVING, -- shift TMS
    ST_SHIFT_PRE, -- Special kind of MOVING where next state is SHIFTING
    ST_SHIFTING,
    ST_SHIFTING_PIPELINE,
    ST_SHIFT_POST, -- Special kind of MOVING where next state is SHIFT_DONE
    ST_SHIFT_DONE
    );

  constant tms_shreg_len : natural := 14;
  
  type regs_t is
  record
    state : state_t;
    tap_branch : tap_branch_t;
    prescaler : natural range 0 to 2 ** prescaler_width - 1;
    data_shreg : std_ulogic_vector(data_max_size-1 downto 0);
    data_shreg_insertion_index, data_left : natural range 0 to data_max_size+1;
    tms_shreg : std_ulogic_vector(0 to tms_shreg_len-1);
    tms_left : natural range 0 to tms_shreg_len;
    tck, tms, tdi : std_ulogic;
    pipelining : boolean;
  end record;

  signal r, rin: regs_t;

  signal rising, falling : boolean;
  
begin

  reg: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.prescaler <= 0;
      r.tck <= '0';
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  rising <= r.tck = '0' and r.prescaler = 0;
  falling <= r.tck /= '0' and r.prescaler = 0;
  
  transition: process(r, jtag_i, cmd_valid_i, cmd_op_i, cmd_data_i, cmd_size_m1_i, rsp_ready_i,
                      rising, falling)
  begin
    rin <= r;

    if r.prescaler /= 0 then
      rin.prescaler <= r.prescaler - 1;
    else
      rin.tck <= not r.tck;
      rin.prescaler <= divisor_i;
    end if;

    if falling then
      rin.tdi <= '-';

      case r.state is
        when ST_IDLE | ST_RESET | ST_SHIFT_DONE =>
          case r.tap_branch is
            when TAP_RESET | TAP_UNDEFINED =>
              rin.tms <= '1';
            when others =>
              rin.tms <= '0';
          end case;

        when ST_MOVING | ST_SHIFT_PRE | ST_SHIFT_POST =>
          rin.tms <= r.tms_shreg(0);

        when ST_SHIFTING | ST_SHIFTING_PIPELINE =>
          if r.data_left = 0 and not r.pipelining then
            rin.tms <= '1';
          end if;
          rin.tdi <= r.data_shreg(0);
      end case;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.prescaler <= divisor_i;

      when ST_IDLE =>
        if cmd_valid_i = '1' and rising then
          rin.pipelining <= false;
          case cmd_op_i is
            when nsl_jtag.ate.ATE_OP_RESET =>
              -- From state * to Reset
              rin.tms_shreg <= (others => '1');
              rin.tms_left <= cmd_size_m1_i;
              rin.tap_branch <= TAP_RESET;
              rin.state <= ST_MOVING;

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
                when TAP_REG =>
                  -- go through Exit2 and Update to Rti
                  rin.tms_shreg <= (others => '0');
                  rin.tms_shreg(0 to 1) <= "11";
                  rin.tms_left <= cmd_size_m1_i + 2;
                  rin.tap_branch <= TAP_RTI;
                  rin.state <= ST_MOVING;
              end case;

            when nsl_jtag.ate.ATE_OP_DR_CAPTURE =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;
                when TAP_RTI =>
                  -- Through Sel-DR, Capture, Ext1 to Pause
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 3) <= "1010";
                  rin.tms_left <= 3;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  -- Loop through Exit2, Update, Sel-DR, Capture, Ext1 to Pause
                  -- Dont touch Rti
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 5) <= "111010";
                  rin.tms_left <= 5;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
              end case;

            when nsl_jtag.ate.ATE_OP_IR_CAPTURE =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;
                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Ext1 to Pause
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 4) <= "11010";
                  rin.tms_left <= 4;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  -- Loop through Exit2, Update, Sel-DR, Sel-IR, Capture, Ext1 to Pause
                  -- Dont touch Rti
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 6) <= "1111010";
                  rin.tms_left <= 6;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
              end case;

            when nsl_jtag.ate.ATE_OP_SWD_TO_JTAG =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET | TAP_RTI =>
                  rin.tms_shreg <= (others => '1');
                  rin.tms_shreg(0 to 12) <= "0011110011100";
                  rin.tms_left <= tms_shreg_len;
                  rin.tap_branch <= TAP_UNDEFINED;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  null;
              end case;

            when nsl_jtag.ate.ATE_OP_SHIFT =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET | TAP_RTI =>
                  null;

                when TAP_REG =>
                  -- From pause, go through Exit2 to Shift
                  rin.tms_shreg <= (others => '-');
                  rin.tms_shreg(0 to 1) <= "10";
                  rin.tms_left <= 1;
                  rin.data_shreg <= cmd_data_i;
                  rin.data_left <= cmd_size_m1_i;
                  rin.data_shreg_insertion_index <= cmd_size_m1_i;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_SHIFT_PRE;
              end case;
          end case;
        end if;

      when ST_MOVING | ST_SHIFT_PRE | ST_SHIFT_POST =>
        if rising then
          if r.tms_left /= 0 then
            -- extend on right, on purpose
            rin.tms_shreg(0 to rin.tms_shreg'right-1) <= r.tms_shreg(1 to r.tms_shreg'right);
            rin.tms_left <= r.tms_left - 1;
          elsif r.state = ST_SHIFT_PRE then
            rin.state <= ST_SHIFTING;
          elsif r.state = ST_SHIFT_POST then
            rin.state <= ST_SHIFT_DONE;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;

      when ST_SHIFTING =>
        -- Remember: We cannot do anything useful on falling in ST_SHIFTING, as we
        -- may sometimes be in SHIFTING_PIPELINE instead.
        if rising then
          rin.data_shreg <= '-' & r.data_shreg(r.data_shreg'left downto 1);
          rin.data_shreg(r.data_shreg_insertion_index) <= jtag_i.tdo;
          if r.data_left = 0 then
            if r.pipelining then
              rin.state <= ST_SHIFTING_PIPELINE;
            else
              -- Basically, we are on a shift underrun. We cannot assert what's
              -- next, so we'll go to pause.
              -- As TMS is 1 on last shift cycle,
              -- on next cycle, we are on Exit1, just go to Pause
              rin.tms_shreg <= (0 => '0',
                                others => '-');
              rin.tms_left <= 0;
              rin.state <= ST_SHIFT_POST;
            end if;
          else
            rin.data_left <= r.data_left - 1;
            -- We need to validate pipelining before we assert TMS up.
            if cmd_valid_i = '1'
              and rsp_ready_i = '1' then
              case cmd_op_i is
                when nsl_jtag.ate.ATE_OP_SHIFT =>
                  rin.pipelining <= true;
                  when others => null;
              end case;
            end if;
          end if;
        end if;

      when ST_SHIFTING_PIPELINE =>
        -- This should last exactly one cycle, in case divisor = 1 (0), it will
        -- be exactly at the same time than the tck-high part of last bit of
        -- word shift.
        -- We already made sure handshake from master was OK, now we'll spend
        -- one (ref) clock cycle to swap shift register values.
        -- On next cycle, we go back as normal in ST_SHIFTING.
        rin.data_shreg <= cmd_data_i;
        rin.data_left <= cmd_size_m1_i;
        rin.data_shreg_insertion_index <= cmd_size_m1_i;
        rin.tap_branch <= TAP_REG;
        rin.pipelining <= false;
        rin.state <= ST_SHIFTING;

        -- Hack for extreme cases where divisor is 0.
        -- In such case, pipeline is executed on "falling" cycle (last cycle
        -- where tck=1). We have to update tdi here.
        if falling then
          rin.tdi <= cmd_data_i(0);
        end if;

      when ST_SHIFT_DONE =>
        if rsp_ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r, rising)
  begin
    cmd_ready_o <= '0';
    rsp_valid_o <= '0';
    rsp_data_o <= (others => '-');

    case r.state is
      when ST_IDLE =>
        if rising then
          cmd_ready_o <= '1';
        end if;

      when ST_SHIFT_DONE =>
        rsp_valid_o <= '1';
        rsp_data_o <= r.data_shreg;

      when ST_SHIFTING_PIPELINE =>
        rsp_valid_o <= '1';
        rsp_data_o <= r.data_shreg;
        cmd_ready_o <= '1';

      when others =>
        null;
    end case;
  end process;

  jtag_o.tck <= r.tck;
  jtag_o.tdi <= r.tdi;
  jtag_o.tms <= r.tms;
  jtag_o.trst <= '0';

end architecture;
