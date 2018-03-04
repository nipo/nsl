library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.i2c.all;

entity i2c_master is
  generic(
    divisor_width : natural
    );
  port(
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_divisor  : in std_ulogic_vector(divisor_width-1 downto 0);

    p_scl       : in  std_ulogic;
    p_scl_drain : out std_ulogic; -- active high drain control
    p_sda       : in  std_ulogic;
    p_sda_drain : out std_ulogic; -- active high drain control

    p_rack     : in  std_ulogic;
    p_rdata    : out std_ulogic_vector(7 downto 0);
    p_wack     : out std_ulogic;
    p_wdata    : in  std_ulogic_vector(7 downto 0);

    p_cmd      : in  i2c_cmd_t;
    p_busy     : out std_ulogic;
    p_done     : out std_ulogic
    );
end entity;

architecture rtl of i2c_master is

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
    ST_IDLE,
    ST_DONE,
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
    started              : std_ulogic;
    bit_count            : natural range 0 to 8;
    ctr                  : natural range 0 to 2 ** (divisor_width + 1) - 1;
  end record;

  signal r, rin : regs_t;

begin

  ck : process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition : process (p_cmd, p_divisor, p_scl, p_sda, p_wdata, r)
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
        rin.state <= ST_IDLE;
        rin.started <= '0';

      when ST_IDLE =>
        case p_cmd is
          when I2C_NOOP =>
            null;

          when I2C_START =>
            step := true;
            if r.started = '1' then
              rin.state <= ST_START_RESTART;
            else
              rin.started <= '1';
              rin.state <= ST_START_IDLE;
            end if;

          when I2C_STOP =>
            if r.started = '1' then
              step := true;
              rin.started <= '0';
              rin.state <= ST_STOP_IDLE;
            else
              rin.state <= ST_DONE;
            end if;

          when I2C_READ | I2C_WRITE =>
            if r.started = '1' then
              step := true;
              rin.state <= ST_BIT_SDA_SETTLE;
              rin.data <= p_wdata;
              rin.ack <= p_rack;
              rin.bit_count <= 8;
            else
              rin.state <= ST_DONE;
            end if;
        end case;

      when ST_START_IDLE =>
        if ready then
          step := true;
          if p_sda = '0' then
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
          rin.state <= ST_DONE;
        end if;

      when ST_START_RECOVER =>
        if ready then
          step := true;
          rin.state <= ST_START_RESTART;
        end if;

      when ST_START_RESTART =>
        if ready then
          step := true;
          if p_sda = '1' then
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
        if p_scl = '1' then
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
          if p_sda = '1' then
            rin.state <= ST_DONE;
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
        if p_scl = '1' then
          double_step := true;
          rin.state <= ST_BIT_SCL_HIGH;
        end if;

      when ST_BIT_SCL_HIGH =>
        if ready then
          rin.state <= ST_BIT_SCL_LOW;
          step := true;
          if r.bit_count /= 0 then
            rin.data <= r.data(6 downto 0) & p_sda;
          else
            rin.ack <= not p_sda;
          end if;
        end if;

      when ST_BIT_SCL_LOW =>
        if ready then
          step := true;
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_BIT_SDA_SETTLE;
          else
            rin.state <= ST_DONE;
          end if;
        end if;

      when ST_DONE =>
        if p_cmd = I2C_NOOP then
          rin.state <= ST_IDLE;
        end if;
    end case;

    if step then
      rin.ctr <= to_integer(unsigned(p_divisor));
    elsif double_step then
      rin.ctr <= to_integer(unsigned(p_divisor)) * 2;
    end if;
  end process;

  moore : process (p_cmd, r)
  begin
    case r.state is
      when ST_IDLE =>
        p_busy <= '0';
        p_done <= '0';

      when ST_DONE =>
        p_done <= '1';
        p_busy <= '1';

      when others =>
        p_done <= '0';
        p_busy <= '1';
    end case;
    
    case r.state is
      when ST_START_SCL
        | ST_START_RESTART
        | ST_BIT_SDA_SETTLE
        | ST_BIT_SCL_LOW
        | ST_STOP_IDLE =>
        p_scl_drain <= '1';
        
      when ST_IDLE
        | ST_DONE =>
        p_scl_drain <= r.started;

      when others =>
        p_scl_drain <= '0';
    end case;

    case r.state is
      when ST_START_SDA
        | ST_START_SCL
        | ST_START_RECOVER
        | ST_STOP_SCL
        | ST_STOP_SCL_RISE
        | ST_STOP_IDLE =>
        p_sda_drain <= '1';

      when ST_IDLE
        | ST_DONE =>
        p_scl_drain <= r.started;

      when ST_BIT_SCL_HIGH
        | ST_BIT_SCL_LOW
        | ST_BIT_SCL_RISE
        | ST_BIT_SDA_SETTLE =>
        if p_cmd = I2C_READ then
          if r.bit_count = 0 then
            p_sda_drain <= r.ack;
          else
            p_sda_drain <= '0';
          end if;
        else
          if r.bit_count = 0 then
            p_sda_drain <= '0';
          else
            p_sda_drain <= not r.data(7);
          end if;
        end if;

      when others =>
        p_sda_drain <= '0';
    end case;

  end process;

  p_rdata <= r.data;
  p_wack <= r.ack;
  
end architecture;
