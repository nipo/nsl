library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity jtag_ate is
  generic (
    data_max_size : positive := 8
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    divisor_i  : in natural range 0 to 31 := 0;

    cmd_ready_o   : out std_ulogic;
    cmd_valid_i   : in  std_ulogic;
    cmd_op_i      : in  nsl.jtag.ate_op;
    cmd_data_i    : in  std_ulogic_vector(data_max_size-1 downto 0);
    cmd_size_m1_i : in  natural range 0 to data_max_size-1;

    rsp_ready_i : in std_ulogic := '1';
    rsp_valid_o : out std_ulogic;
    rsp_data_o  : out std_ulogic_vector(data_max_size-1 downto 0);

    tck_o  : out std_ulogic;
    tms_o  : out std_ulogic;
    tdi_o  : out std_ulogic;
    tdo_i  : in  std_ulogic
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
    ST_SHIFT_POST, -- Special kind of MOVING where next state is SHIFT_DONE
    ST_SHIFT_DONE
    );
  
  type regs_t is
  record
    state : state_t;
    tap_branch : tap_branch_t;
    prescaler : natural range 0 to 31;
    data_shreg : std_ulogic_vector(data_max_size-1 downto 0);
    data_shreg_insertion_index, data_left : natural range 0 to data_max_size+1;
    tms_shreg : std_ulogic_vector(7 downto 0);
    tms_left : natural range 0 to 9;
    tck : std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  reg: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.prescaler <= 0;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, tdo_i, cmd_valid_i, cmd_op_i, cmd_data_i, cmd_size_m1_i, rsp_ready_i)
    variable rising, falling : boolean;
  begin
    rin <= r;

    rising := false;
    falling := false;
    
    if r.prescaler = 0 then
      if r.tck = '0' then
        rising := true;
        rin.tck <= '1';
      else
        falling := true;
        rin.tck <= '0';
      end if;
    end if;

    if r.prescaler /= 0 then
      rin.prescaler <= r.prescaler - 1;
    else
      rin.prescaler <= divisor_i;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.prescaler <= divisor_i;
        
      when ST_IDLE =>
        if cmd_valid_i = '1' and falling then
          case cmd_op_i is
            when nsl.jtag.ATE_OP_RESET =>
              -- From state * to Reset
              rin.tms_shreg <= (others => '1');
              rin.tms_left <= cmd_size_m1_i;
              rin.tap_branch <= TAP_RESET;
              rin.state <= ST_MOVING;

            when nsl.jtag.ATE_OP_RTI =>
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
                  rin.tms_shreg <= "00000011";
                  rin.tms_left <= cmd_size_m1_i + 2;
                  rin.tap_branch <= TAP_RTI;
                  rin.state <= ST_MOVING;
              end case;

            when nsl.jtag.ATE_OP_DR_CAPTURE =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;
                when TAP_RTI =>
                  -- Through Sel-DR, Capture, Ext1 to Pause
                  rin.tms_shreg <= "----0101";
                  rin.tms_left <= 3;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  -- Loop through Exit2, Update, Sel-DR, Capture, Ext1 to Pause
                  -- Dont touch Rti
                  rin.tms_shreg <= "--010111";
                  rin.tms_left <= 5;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
              end case;

            when nsl.jtag.ATE_OP_IR_CAPTURE =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET =>
                  null;
                when TAP_RTI =>
                  -- Through Sel-DR, Sel-IR, Capture, Ext1 to Pause
                  rin.tms_shreg <= "---01011";
                  rin.tms_left <= 4;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  -- Loop through Exit2, Update, Sel-DR, Sel-IR, Capture, Ext1 to Pause
                  -- Dont touch Rti
                  rin.tms_shreg <= "-0101111";
                  rin.tms_left <= 6;
                  rin.tap_branch <= TAP_REG;
                  rin.state <= ST_MOVING;
              end case;

            when nsl.jtag.ATE_OP_SWD_TO_JTAG_3 =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET | TAP_RTI =>
                  rin.tms_shreg <= "--111100";
                  rin.tms_left <= 5;
                  rin.tap_branch <= TAP_UNDEFINED;
                  rin.state <= ST_MOVING;
                when TAP_REG =>
                  null;
              end case;

            when nsl.jtag.ATE_OP_SHIFT =>
              case r.tap_branch is
                when TAP_UNDEFINED | TAP_RESET | TAP_RTI =>
                  null;

                when TAP_REG =>
                  -- From pause, go through Exit2 to Shift
                  rin.tms_shreg <= "------01";
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
            -- extend on left, on purpose
            rin.tms_shreg(rin.tms_shreg'left-1 downto 0) <= r.tms_shreg(r.tms_shreg'left downto 1);
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
        if rising then
          rin.data_shreg <= '-' & r.data_shreg(r.data_shreg'left downto 1);
          rin.data_shreg(r.data_shreg_insertion_index) <= tdo_i;
          rin.data_left <= r.data_left - 1;
          if r.data_left = 0 then
            -- On next cycle, we are on Exit1, just go to Pause
            rin.tms_shreg <= "-------0";
            rin.tms_left <= 0;
            rin.state <= ST_SHIFT_POST;
          end if;
        end if;

      when ST_SHIFT_DONE =>
        if rsp_ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    cmd_ready_o <= '0';
    rsp_valid_o <= '0';
    rsp_data_o <= (others => '-');

    case r.state is
      when ST_IDLE =>
        if r.prescaler = 0 and r.tck /= '0' then
            cmd_ready_o <= '1';
        end if;

      when ST_SHIFT_DONE =>
        rsp_valid_o <= '1';
        rsp_data_o <= r.data_shreg;

      when others =>
        null;
    end case;
  end process;

  jtag_moore: process(r)
  begin
    tck_o <= r.tck;

    if r.prescaler = 0 and r.tck = '0' then
      tms_o <= '0';
      tdi_o <= '-';

      case r.state is
        when ST_MOVING | ST_SHIFT_PRE | ST_SHIFT_POST =>
          tms_o <= r.tms_shreg(0);

        when ST_SHIFTING =>
          if r.data_left = 0 then
            tms_o <= '1';
          end if;
          tdi_o <= r.data_shreg(0);

      when others =>
        null;
      end case;
    end if;
  end process;

end architecture;
