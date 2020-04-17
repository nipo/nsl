library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;
use nsl_i2c.transactor.all;

entity transactor_master is
  generic(
    divisor_width : natural
    );
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    divisor_i  : in std_ulogic_vector(divisor_width-1 downto 0);

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i;

    rack_i     : in  std_ulogic;
    rdata_o    : out std_ulogic_vector(7 downto 0);
    wack_o     : out std_ulogic;
    wdata_i    : in  std_ulogic_vector(7 downto 0);

    cmd_i      : in  i2c_cmd_t;
    busy_o     : out std_ulogic;
    done_o     : out std_ulogic
    );
end entity;

architecture rtl of transactor_master is

  -- Start condition
  --          ___     _______
  -- SCL  ___/   \___/       \____
  --
  --         |   |   |   |   |
  --               ______
  -- SDA  ________/_/    \________
  --
  --         |   |   |   |   |
  --       ^   ^   ^   ^   ^   ^
  --       |   |   |   |   |   \-- START_SCL
  --       |   |   |   |   \------ START_SDA
  --       |   |   |   \---------- START_IDLE
  --       |   |   \-- ----------- START_RESTART
  --       |   \------------------ START_RECOVER
  --       \---------------------- START_RESTART
  --       ^           ^   ^
  --       |           |   \---- Usual start point
  --       |           \-------- Usual restart point
  --       \------------ Can happen if slave holds SDA,
  --                     Should toggle SCL until SDA rises

  -- Bit transmission
  --         /----------- SDA Update point
  --         |          /---- SDA Sample point
  --         v          v
  --               ______
  -- SCL  ________/__/   \_______
  --                         
  --         |   |   |   |   |
  --      ___ _______________ ___
  -- SDA  ___X_______________X___
  --                         
  --         |   |   |   |   |
  --           ^   ^   ^   ^
  --           |   |   |   \-- SCL_LOW
  --           |   |   \------ SCL_HIGH
  --           |   \---------- SCL_RISE
  --           \-------------- SDA_SETTLE

  -- Stop condition
  --          __________      __________
  -- SCL  ___/__/       \____/__/
  --                            
  --        |   |   |   |   |   |   |
  --                 !!!             ___
  -- SDA  __________________________/
  --                            
  --        |   |   |   |   |   |   |
  --      ^   ^   ^   ^   ^   ^   ^   ^
  --      |   |   |   |   |   |   |   \-- STOP_SDA
  --      |   |   |   |   |   |   \------ STOP_SCL
  --      |   |   |   |   |   \---------- STOP_SCL_RISE
  --      |   |   |   |   \-------------- STOP_IDLE
  --      |   |   |   \------------------ STOP_SDA
  --      |   |   \---------------------- STOP_SCL
  --      |   \-------------------------- STOP_SCL_RISE
  --      \------------------------------ STOP_IDLE
  --                   ^   ^
  --                   |   \---- Usual start point for stop
  --                   \---- Can happen if slave holds SDA,
  --                         Should toggle SCL until SDA rises

  type state_t is (
    ST_RESET,
    ST_IDLE_STARTED,
    ST_DONE_STARTED,
    ST_IDLE_STOPPED,
    ST_DONE_STOPPED,
    ST_START_IDLE,
    ST_START_RESTART,
    ST_START_SDA,
    ST_START_SCL,
    ST_START_RECOVER,
    ST_STOP_IDLE,
    ST_STOP_SCL_RISE,
    ST_STOP_SCL,
    ST_STOP_SDA,
    ST_BIT_SDA_SETTLE,
    ST_BIT_SCL_RISE,
    ST_BIT_SCL_HIGH,
    ST_BIT_SCL_LOW
    );

  type regs_t is record
    state                : state_t;
    data                 : std_ulogic_vector(7 downto 0);
    ack                  : std_ulogic;
    sda                  : std_ulogic;
    wait_stop            : std_ulogic;
    bit_count            : natural range 0 to 8;
    ctr                  : natural range 0 to 2 ** (divisor_width + 1) - 1;
  end record;

  signal r, rin : regs_t;

begin

  ck : process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition : process (cmd_i, divisor_i, i2c_i, wdata_i, r, rack_i)
    variable ready, step, double_step : boolean;
  begin
    rin <= r;

    step := false;
    double_step := false;
    if r.ctr /= 0 then
      rin.ctr <= r.ctr - 1;
      ready := false;
    else
      ready := true;
    end if;

    case r.state is
      when ST_RESET =>
        step := true;
        rin.state <= ST_IDLE_STOPPED;
        rin.wait_stop <= '0';

      when ST_IDLE_STOPPED =>
        case cmd_i is
          when I2C_NOOP =>
            null;

          when I2C_START =>
            if rin.wait_stop = '1' then
              rin.state <= ST_DONE_STOPPED;
            else
              step := true;
              rin.state <= ST_START_IDLE;
            end if;

          when I2C_STOP =>
            rin.state <= ST_DONE_STOPPED;
            rin.wait_stop <= '0';

          when I2C_READ | I2C_WRITE =>
            rin.state <= ST_DONE_STOPPED;
        end case;

      when ST_IDLE_STARTED =>
        case cmd_i is
          when I2C_NOOP =>
            null;

          when I2C_START =>
            step := true;
            rin.state <= ST_START_RESTART;

          when I2C_STOP =>
            step := true;
            rin.state <= ST_STOP_IDLE;

          when I2C_READ | I2C_WRITE =>
            step := true;
            rin.state <= ST_BIT_SDA_SETTLE;
            rin.data <= wdata_i;
            rin.sda <= wdata_i(7);
            rin.ack <= rack_i;
            rin.bit_count <= 8;
        end case;

      when ST_START_IDLE =>
        if ready then
          step := true;
          if to_x01(i2c_i.sda) = '0' then
            rin.state <= ST_START_RECOVER;
          else
            rin.state <= ST_START_SDA;
          end if;
        end if;

      when ST_START_SDA =>
        if ready then
          step := true;
          rin.state <= ST_START_SCL;
        end if;

      when ST_START_SCL =>
        if ready then
          step := true;
          rin.state <= ST_DONE_STARTED;
        end if;

      when ST_START_RECOVER =>
        if ready then
          step := true;
          rin.state <= ST_START_RESTART;
        end if;

      when ST_START_RESTART =>
        if ready then
          step := true;
          if to_x01(i2c_i.sda) = '1' then
            rin.state <= ST_START_IDLE;
          else
            rin.state <= ST_START_RECOVER;
          end if;
        end if;

      when ST_STOP_IDLE =>
        if ready then
          rin.state <= ST_STOP_SCL_RISE;
        end if;

      when ST_STOP_SCL_RISE =>
        if to_x01(i2c_i.scl) = '1' then
          step := true;
          rin.state <= ST_STOP_SCL;
        end if;

      when ST_STOP_SCL =>
        if ready then
          step := true;
          rin.state <= ST_STOP_SDA;
        end if;

      when ST_STOP_SDA =>
        if ready then
          step := true;
          if to_x01(i2c_i.sda) = '1' then
            rin.state <= ST_DONE_STOPPED;
          else
            rin.state <= ST_STOP_IDLE;
          end if;
        end if;

      when ST_BIT_SDA_SETTLE =>
        if ready then
          step := true;
          rin.state <= ST_BIT_SCL_RISE;
        end if;

      when ST_BIT_SCL_RISE =>
        if to_x01(i2c_i.scl) = '1' then
          double_step := true;
          rin.state <= ST_BIT_SCL_HIGH;
        end if;

      when ST_BIT_SCL_HIGH =>
        if ready then
          rin.state <= ST_BIT_SCL_LOW;
          step := true;
          if r.bit_count /= 0 then
            rin.data <= r.data(6 downto 0) & to_x01(i2c_i.sda);
          else
            rin.ack <= not to_x01(i2c_i.sda);
          end if;
        end if;

      when ST_BIT_SCL_LOW =>
        if ready then
          step := true;
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_BIT_SDA_SETTLE;
            rin.sda <= r.data(7);
          elsif cmd_i = I2C_WRITE and r.ack = '0' then
            rin.wait_stop <= '1';
            rin.state <= ST_STOP_IDLE;
          else
            rin.state <= ST_DONE_STARTED;
          end if;
        end if;

      when ST_DONE_STARTED =>
        if cmd_i = I2C_NOOP then
          rin.state <= ST_IDLE_STARTED;
        end if;

      when ST_DONE_STOPPED =>
        if cmd_i = I2C_NOOP then
          rin.state <= ST_IDLE_STOPPED;
        end if;
    end case;

    if step then
      rin.ctr <= to_integer(to_01(unsigned(divisor_i), '0'));
    elsif double_step then
      rin.ctr <= to_integer(to_01(unsigned(divisor_i), '0')) * 2;
    end if;
  end process;

  moore : process (cmd_i, r)
  begin
    case r.state is
      when ST_IDLE_STOPPED | ST_IDLE_STARTED =>
        busy_o <= '0';
        done_o <= '0';

      when ST_DONE_STOPPED | ST_DONE_STARTED =>
        done_o <= '1';
        busy_o <= '1';

      when others =>
        done_o <= '0';
        busy_o <= '1';
    end case;
    
    case r.state is
      when ST_IDLE_STOPPED
        | ST_DONE_STOPPED
        | ST_START_IDLE
        | ST_RESET
        | ST_START_RECOVER
        | ST_START_SDA
        | ST_STOP_SCL_RISE
        | ST_STOP_SCL
        | ST_STOP_SDA
        | ST_BIT_SCL_RISE
        | ST_BIT_SCL_HIGH =>
        i2c_o.scl.drain <= '0';

      when ST_IDLE_STARTED
        | ST_DONE_STARTED
        | ST_START_RESTART
        | ST_START_SCL
        | ST_STOP_IDLE
        | ST_BIT_SDA_SETTLE
        | ST_BIT_SCL_LOW =>
        i2c_o.scl.drain <= '1';
    end case;

    case r.state is
      when ST_START_SDA
        | ST_START_SCL
        | ST_START_RECOVER
        | ST_STOP_SCL
        | ST_STOP_SCL_RISE
        | ST_STOP_IDLE
        | ST_DONE_STARTED
        | ST_IDLE_STARTED =>
        i2c_o.sda.drain <= '1';

      when ST_BIT_SCL_HIGH
        | ST_BIT_SCL_LOW
        | ST_BIT_SCL_RISE
        | ST_BIT_SDA_SETTLE =>
        if cmd_i = I2C_READ then
          if r.bit_count = 0 then
            i2c_o.sda.drain <= r.ack;
          else
            i2c_o.sda.drain <= '0';
          end if;
        else
          if r.bit_count = 0 then
            i2c_o.sda.drain <= '0';
          else
            i2c_o.sda.drain <= not r.sda;
          end if;
        end if;

      when others =>
        i2c_o.sda.drain <= '0';
    end case;

  end process;

  rdata_o <= r.data;
  wack_o <= r.ack;
  
end architecture;
