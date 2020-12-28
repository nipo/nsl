library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_math, nsl_spi, nsl_ti;
use nsl_spi.transactor.all;
use nsl_bnoc.framed.all;
use nsl_math.fixed.all;
use nsl_ti.dacx0508.all;

entity dacx0508_slope_controller is
  generic(
    dac_resolution_c : integer range 12 to 16 := 16;
    increment_msb_c : integer range 0 to 15 := 7;
    increment_lsb_c : integer range -16 to 0 := -8;
    min_command_interval_c : natural range 1 to 10000000 := 1;
    max_pending_command_c : natural range 1 to 511 := 1
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    div_i       : in unsigned(4 downto 0);
    cs_id_i     : in unsigned(2 downto 0);

    slave_cmd_i : in  framed_req;
    slave_cmd_o : out framed_ack;
    slave_rsp_o : out framed_req;
    slave_rsp_i : in  framed_ack;

    master_cmd_o : out framed_req;
    master_cmd_i : in  framed_ack;
    master_rsp_i : in  framed_req;
    master_rsp_o : out framed_ack
    );
end entity;

architecture beh of dacx0508_slope_controller is

  subtype target_t is  ufixed(dac_resolution_c-1 downto 0);
  subtype current_t is  ufixed(dac_resolution_c-1 downto increment_lsb_c-1);
  subtype increment_t is ufixed(increment_msb_c downto increment_lsb_c-1);

  type slave_state_t is (
    ST_SLAVE_RESET,
    ST_SLAVE_IDLE,
    ST_SLAVE_DATA_GET,
    ST_SLAVE_EXEC,
    ST_SLAVE_RSP
    );

  type computer_state_t is (
    ST_COMPUTER_IDLE,
    ST_COMPUTER_DIRECTION_SENSE,
    ST_COMPUTER_STOP_CALC,
    ST_COMPUTER_RUN
    );

  type master_cmd_state_t is (
    ST_MASTER_CMD_RESET,
    ST_MASTER_CMD_IDLE,
    ST_MASTER_CMD_DIV,
    ST_MASTER_CMD_CS,
    ST_MASTER_CMD_SHIFT_OP,
    ST_MASTER_CMD_SHIFT_CMD,
    ST_MASTER_CMD_SHIFT_DATA0,
    ST_MASTER_CMD_SHIFT_DATA1,
    ST_MASTER_CMD_UNCS
    );

  type master_rsp_state_t is (
    ST_MASTER_RSP_RESET,
    ST_MASTER_RSP_IDLE,
    ST_MASTER_RSP_WAIT
    );

  type regs_t is
  record
    slave_state : slave_state_t;
    master_cmd_state : master_cmd_state_t;
    master_rsp_state : master_rsp_state_t;
    computer_state : computer_state_t;

    -- Target register to talk to
    target_reg : std_ulogic_vector(2 downto 0);

    -- Computer state
    current : current_t;
    target : target_t;
    stop : target_t;
    increment : increment_t;
    substract : boolean;
    -- Whether current changed since last sent command
    current_dirty : boolean;
    -- Whether slave command changed parameters
    increment_changed : boolean;
    target_changed : boolean;

    -- Snapshot of current value for master FSM to avoid tearing
    dac_val : target_t;

    -- Slave command, last state, input buffer
    cmd : framed_data_t;
    last : std_ulogic;
    data_in : std_ulogic_vector(31 downto 0);
    data_left : natural range 0 to 3;

    -- Command backoff
    cmd_left_before_next : natural range 0 to min_command_interval_c-1;
    cmd_allowed_count : natural range 0 to max_pending_command_c;
  end record;
      
  signal r, rin : regs_t;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.slave_state <= ST_SLAVE_RESET;
      r.master_cmd_state <= ST_MASTER_CMD_RESET;
      r.master_rsp_state <= ST_MASTER_RSP_RESET;
      r.computer_state <= ST_COMPUTER_IDLE;
      r.increment_changed <= false;
      r.target_changed <= false;
      r.current_dirty <= false;
      r.increment <= (others => '0');
      r.current <= (others => '0');
      r.target <= (others => '0');
      r.target_reg <= (others => '0');
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, slave_cmd_i, slave_rsp_i, master_cmd_i, master_rsp_i)
    variable command_started, command_ended : boolean;
    variable w_increment, w_target : current_t;
  begin
    rin <= r;

    command_started := false;
    command_ended := false;
    w_increment := resize(r.increment, w_increment'left, w_increment'right);
    w_target := resize(r.target, w_target'left, w_target'right);

    case r.slave_state is
      when ST_SLAVE_RESET =>
        rin.slave_state <= ST_SLAVE_IDLE;

      when ST_SLAVE_IDLE =>
        if slave_cmd_i.valid = '1' then
          rin.cmd <= slave_cmd_i.data;
          rin.last <= slave_cmd_i.last;

          if std_match(slave_cmd_i.data, DACX0508_CMD_CURRENT_SET)
            or std_match(slave_cmd_i.data, DACX0508_CMD_TARGET_SET) then
            rin.data_left <= 1;
            rin.slave_state <= ST_SLAVE_DATA_GET;
          elsif std_match(slave_cmd_i.data, DACX0508_CMD_INCREMENT_SET) then
            rin.data_left <= 3;
            rin.slave_state <= ST_SLAVE_DATA_GET;
          else
            rin.slave_state <= ST_SLAVE_RSP;
          end if;
        end if;

      when ST_SLAVE_DATA_GET =>
        if slave_cmd_i.valid = '1' then
          rin.data_in <= r.data_in(23 downto 0) & slave_cmd_i.data;
          rin.last <= slave_cmd_i.last;
          if r.data_left /= 0 then
            rin.data_left <= r.data_left - 1;
          else
            rin.slave_state <= ST_SLAVE_EXEC;
          end if;
        end if;

      when ST_SLAVE_EXEC =>
        if std_match(r.cmd, DACX0508_CMD_CURRENT_SET) then
          rin.current <= (others => '0');
          rin.current(target_t'range) <= ufixed(r.data_in(target_t'range));
          rin.target <= ufixed(r.data_in(target_t'range));
          rin.target_reg <= r.cmd(2 downto 0);
        elsif std_match(r.cmd, DACX0508_CMD_TARGET_SET) then
          rin.target_changed <= true;
          rin.target <= ufixed(r.data_in(target_t'range));
        else
          rin.increment_changed <= true;
          rin.increment(increment_msb_c downto increment_lsb_c)
            <= ufixed(r.data_in(increment_msb_c+16 downto increment_lsb_c+16));
        end if;
        rin.slave_state <= ST_SLAVE_RSP;

      when ST_SLAVE_RSP =>
        if slave_rsp_i.ready = '1' then
          rin.slave_state <= ST_SLAVE_IDLE;
        end if;

    end case;

    case r.master_cmd_state is
      when ST_MASTER_CMD_RESET =>
        rin.master_cmd_state <= ST_MASTER_CMD_IDLE;

      when ST_MASTER_CMD_IDLE =>
        if r.current_dirty
          and r.cmd_left_before_next = 0
          and r.cmd_allowed_count /= 0 then
          command_started := true;
          rin.cmd_left_before_next <= min_command_interval_c-1;
          rin.master_cmd_state <= ST_MASTER_CMD_DIV;
          rin.dac_val <= r.current(rin.dac_val'range);
          rin.current_dirty <= false;
        end if;

      when ST_MASTER_CMD_DIV =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_CS;
        end if;

      when ST_MASTER_CMD_CS =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_SHIFT_OP;
        end if;

      when ST_MASTER_CMD_SHIFT_OP =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_SHIFT_CMD;
        end if;

      when ST_MASTER_CMD_SHIFT_CMD =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_SHIFT_DATA0;
        end if;

      when ST_MASTER_CMD_SHIFT_DATA0 =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_SHIFT_DATA1;
        end if;

      when ST_MASTER_CMD_SHIFT_DATA1 =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_UNCS;
        end if;

      when ST_MASTER_CMD_UNCS =>
        if master_cmd_i.ready = '1' then
          rin.master_cmd_state <= ST_MASTER_CMD_IDLE;
        end if;
    end case;
    
    case r.master_rsp_state is
      when ST_MASTER_RSP_RESET =>
        rin.master_rsp_state <= ST_MASTER_RSP_IDLE;
        rin.cmd_left_before_next <= min_command_interval_c - 1;
        rin.cmd_allowed_count <= max_pending_command_c;

      when ST_MASTER_RSP_IDLE =>
        if r.master_cmd_state = ST_MASTER_CMD_CS then
          rin.master_rsp_state <= ST_MASTER_RSP_WAIT;
        end if;

      when ST_MASTER_RSP_WAIT =>
        if master_rsp_i.valid = '1' and master_rsp_i.last = '1' then
          command_ended := true;
          rin.master_rsp_state <= ST_MASTER_RSP_IDLE;
        end if;
    end case;

    if command_ended
      and not command_started
      and r.cmd_allowed_count /= max_pending_command_c then
      rin.cmd_allowed_count <= r.cmd_allowed_count + 1;
    elsif not command_ended and command_started and r.cmd_allowed_count /= 0 then
      rin.cmd_allowed_count <= r.cmd_allowed_count - 1;
    end if;

    if r.cmd_left_before_next /= 0 then
      rin.cmd_left_before_next <= r.cmd_left_before_next - 1;
    end if;
    
    case r.computer_state is
      when ST_COMPUTER_IDLE =>
        if r.target_changed then
          rin.computer_state <= ST_COMPUTER_DIRECTION_SENSE;
        end if;

      when ST_COMPUTER_DIRECTION_SENSE =>
        rin.increment_changed <= false;
        rin.target_changed <= false;
        rin.substract <= r.target < r.current(r.target'range);

        if r.increment = (r.increment'range => '0') then
          rin.increment(0) <= '1';
        end if;

        if r.current(r.target'range) = r.target then
          rin.computer_state <= ST_COMPUTER_IDLE;
        else
          rin.computer_state <= ST_COMPUTER_STOP_CALC;
        end if;

      when ST_COMPUTER_STOP_CALC =>
        if r.substract then
          rin.stop <= resize(w_target + w_increment, r.stop'left, r.stop'right);
        else
          rin.stop <= resize(w_target - w_increment, r.stop'left, r.stop'right);
        end if;
        rin.computer_state <= ST_COMPUTER_RUN;

      when ST_COMPUTER_RUN =>
        if r.increment_changed or r.target_changed then
          rin.computer_state <= ST_COMPUTER_DIRECTION_SENSE;
        elsif r.substract then
          rin.current_dirty <= true;
          if r.current(r.stop'range) > r.stop then
            rin.current <= r.current - w_increment;
          else
            rin.current <= w_target;
            rin.computer_state <= ST_COMPUTER_IDLE;
          end if;
        else
          rin.current_dirty <= true;
          if r.current(r.stop'range) < r.stop then
            rin.current <= r.current + w_increment;
          else
            rin.current <= w_target;
            rin.computer_state <= ST_COMPUTER_IDLE;
          end if;
        end if;
    end case;

  end process;

  moore: process(r, cs_id_i, div_i)
  begin
    slave_cmd_o.ready <= '0';
    slave_rsp_o.valid <= '0';
    slave_rsp_o.data <= (others => '-');
    slave_rsp_o.last <= '-';
    master_cmd_o.valid <= '0';
    master_cmd_o.data <= (others => '-');
    master_cmd_o.last <= '-';
    master_rsp_o.ready <= '0';

    case r.slave_state is
      when ST_SLAVE_RESET | ST_SLAVE_EXEC =>
        null;

      when ST_SLAVE_IDLE | ST_SLAVE_DATA_GET =>
        slave_cmd_o.ready <= '1';

      when ST_SLAVE_RSP =>
        slave_rsp_o.valid <= '1';
        slave_rsp_o.data <= r.cmd;
        slave_rsp_o.last <= r.last;
    end case;

    case r.master_cmd_state is
      when ST_MASTER_CMD_RESET | ST_MASTER_CMD_IDLE =>
        null;

      when ST_MASTER_CMD_DIV =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= SPI_CMD_DIV(7 downto 5)
                             & std_ulogic_vector(div_i);
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_CS =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= SPI_CMD_SELECT(7 downto 5)
                             & SPI_CMD_SELECT_MODE1(4 downto 3)
                             & std_ulogic_vector(cs_id_i);
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_SHIFT_OP =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= SPI_CMD_SHIFT_OUT(7 downto 6)
                             & "000010"; -- Shift 3 bytes
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_SHIFT_CMD =>
        master_cmd_o.valid <= '1';
        -- [D---RRRR] with D = 0 for Write, RRRR = 8 + target_reg
        master_cmd_o.data <= "00001" & r.target_reg;
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_SHIFT_DATA0 =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= (others => '0');
        master_cmd_o.data(r.dac_val'left-8 downto 0)
          <= std_ulogic_vector(r.dac_val(r.dac_val'left downto 8));
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_SHIFT_DATA1 =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= std_ulogic_vector(r.dac_val(7 downto 0));
        master_cmd_o.last <= '0';

      when ST_MASTER_CMD_UNCS =>
        master_cmd_o.valid <= '1';
        master_cmd_o.data <= SPI_CMD_UNSELECT(7 downto 5)
                             & SPI_CMD_SELECT_MODE1(4 downto 3)
                             & SPI_CMD_UNSELECT(2 downto 0);
        master_cmd_o.last <= '1';
    end case;
    
    case r.master_rsp_state is
      when ST_MASTER_RSP_RESET | ST_MASTER_RSP_IDLE =>
        null;

      when ST_MASTER_RSP_WAIT =>
        master_rsp_o.ready <= '1';
    end case;

  end process;
  
end architecture;
