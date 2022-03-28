library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;
use nsl_i2c.master.all;

entity master_clock_driver is
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    half_cycle_clock_count_i  : in unsigned;

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i;

    ready_o : out std_ulogic;
    valid_i : in std_ulogic;
    cmd_i : in i2c_bus_cmd_t;

    abort_i : in std_ulogic;
    failed_o : out std_ulogic;
    owned_o : out std_ulogic
    );
end entity;

architecture beh of master_clock_driver is

  type state_t is (
    ST_RESET,

    ST_FAILED,
    ST_READY,
    ST_EXEC,

    ST_RESTART_PRE,
    ST_RESTART_SDA_RISE,
    ST_RESTART_SDA_HIGH,
    ST_RESTART_SCL_RISE,
    ST_RESTART_SCL_HIGH,

    ST_START_PRE,
    ST_START_SDA_FALL,
    ST_START_SDA_LOW,
    ST_START_SCL_FALL,
    ST_START_SCL_LOW,
    
    ST_BYTE_PRE,
    ST_BIT_SCL_RISE,
    ST_BIT_SCL_HIGH,
    ST_BIT_SCL_FALL,
    ST_BIT_SCL_LOW,

    ST_STOP_PRE,
    ST_STOP_SCL_RISE,
    ST_STOP_SCL_HIGH,
    ST_STOP_SDA_RISE,
    ST_STOP_SDA_HIGH
    );

  type bus_state_t is (
    BUS_RESET,
    BUS_BUSY,
    BUS_FREE,
    BUS_OWNED
    );
  
  signal idle_timeout_clock_count_i : unsigned(half_cycle_clock_count_i'length + 3 downto 0);
  signal stuck_timeout_clock_count_i : unsigned(half_cycle_clock_count_i'length + 2 downto 0);
  
  type regs_t is record
    state     : state_t;
    bus_state : bus_state_t;
    cmd : i2c_bus_cmd_t;
    bit_count : natural range 0 to 8;
    idle_timeout : unsigned(idle_timeout_clock_count_i'range);
    half_cycle : unsigned(half_cycle_clock_count_i'range);
    stuck_timeout : unsigned(stuck_timeout_clock_count_i'range);
  end record;

  signal r, rin : regs_t;

begin

  idle_timeout_clock_count_i <= half_cycle_clock_count_i & "1000";
  stuck_timeout_clock_count_i <= half_cycle_clock_count_i & "100";
  
  ck : process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.bus_state <= BUS_FREE;
    end if;
  end process;

  transition : process (i2c_i, r, valid_i, cmd_i, abort_i,
                        half_cycle_clock_count_i,
                        idle_timeout_clock_count_i,
                        stuck_timeout_clock_count_i)
  begin
    rin <= r;

    case r.bus_state is
      when BUS_RESET =>
        rin.idle_timeout <= idle_timeout_clock_count_i;
        rin.bus_state <= BUS_BUSY;

      when BUS_BUSY =>
        rin.idle_timeout <= r.idle_timeout - 1;
        if i2c_i.sda = '0' or i2c_i.scl = '0' then
          rin.idle_timeout <= idle_timeout_clock_count_i;
        elsif r.idle_timeout = 0 then
          rin.bus_state <= BUS_FREE;
        end if;

      when BUS_FREE =>
        if i2c_i.sda = '0' or i2c_i.scl = '0' then
          rin.idle_timeout <= idle_timeout_clock_count_i;
          rin.bus_state <= BUS_BUSY;
        end if;

      when BUS_OWNED =>
        null;
    end case;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_READY;

      when ST_FAILED =>
        rin.state <= ST_READY;
        rin.bus_state <= BUS_BUSY;

      when ST_READY =>
        if valid_i = '1' then
          rin.cmd <= cmd_i;
          rin.state <= ST_EXEC;
        end if;

      when ST_EXEC =>
        rin.half_cycle <= half_cycle_clock_count_i;
        case r.cmd is
          when I2C_BUS_START =>
            case r.bus_state is
              when BUS_FREE =>
                rin.state <= ST_START_PRE;
                rin.bus_state <= BUS_OWNED;

              when BUS_BUSY | BUS_RESET =>
                null;

              when BUS_OWNED =>
                rin.state <= ST_RESTART_PRE;
            end case;

          when I2C_BUS_BYTE =>
            case r.bus_state is
              when BUS_FREE | BUS_BUSY | BUS_RESET =>
                rin.state <= ST_READY;

              when BUS_OWNED =>
                rin.state <= ST_BYTE_PRE;
            end case;

          when I2C_BUS_STOP =>
            case r.bus_state is
              when BUS_FREE | BUS_BUSY | BUS_RESET =>
                rin.state <= ST_READY;

              when BUS_OWNED =>
                rin.state <= ST_STOP_PRE;
                -- Actually, setting this here would trigger BUS_BUSY,
                --rin.bus_state <= BUS_FREE;
            end case;
        end case;

      -- Start operation
      when ST_START_PRE =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_START_SDA_FALL;
        end if;

      when ST_START_SDA_FALL =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.sda = '0' then
          rin.state <= ST_START_SDA_LOW;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;
        
      when ST_START_SDA_LOW =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_START_SCL_FALL;
        end if;

      when ST_START_SCL_FALL =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.scl = '0' then
          rin.state <= ST_START_SCL_LOW;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;
        
      when ST_START_SCL_LOW =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.state <= ST_READY;
        end if;

      -- Byte operation
      when ST_BYTE_PRE =>
        rin.half_cycle <= r.half_cycle - 1;
        rin.bit_count <= 8;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_BIT_SCL_RISE;
        end if;

      when ST_BIT_SCL_RISE =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.scl = '1' then
          rin.state <= ST_BIT_SCL_HIGH;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_BIT_SCL_HIGH =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_BIT_SCL_FALL;
        end if;

      when ST_BIT_SCL_FALL =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.scl = '0' then
          rin.state <= ST_BIT_SCL_LOW;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_BIT_SCL_LOW =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          if r.bit_count /= 0 then
            rin.bit_count <= r.bit_count - 1;
            rin.state <= ST_BIT_SCL_RISE;
          else
            rin.state <= ST_READY;
          end if;
        end if;

      -- Stop
      when ST_STOP_PRE =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_STOP_SCL_RISE;
        end if;

      when ST_STOP_SCL_RISE =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.scl = '1' then
          rin.state <= ST_STOP_SCL_HIGH;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_STOP_SCL_HIGH =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_STOP_SDA_RISE;
        end if;

      when ST_STOP_SDA_RISE =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.sda = '1' then
          rin.state <= ST_STOP_SDA_HIGH;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_STOP_SDA_HIGH =>
        rin.half_cycle <= r.half_cycle - 1;
        rin.bus_state <= BUS_FREE;
        if r.half_cycle = 0 then
          rin.state <= ST_READY;
        end if;

      -- Restart
      when ST_RESTART_PRE =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_RESTART_SDA_RISE;
        end if;

      when ST_RESTART_SDA_RISE =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.sda = '1' then
          rin.state <= ST_RESTART_SDA_HIGH;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_RESTART_SDA_HIGH =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_RESTART_SCL_RISE;
        end if;

      when ST_RESTART_SCL_RISE =>
        rin.half_cycle <= half_cycle_clock_count_i;
        if i2c_i.scl = '1' then
          rin.state <= ST_RESTART_SCL_HIGH;
        elsif r.stuck_timeout /= 0 then
          rin.stuck_timeout <= r.stuck_timeout - 1;
        else
          rin.state <= ST_FAILED;
        end if;

      when ST_RESTART_SCL_HIGH =>
        rin.half_cycle <= r.half_cycle - 1;
        if r.half_cycle = 0 then
          rin.stuck_timeout <= stuck_timeout_clock_count_i;
          rin.state <= ST_START_SDA_FALL;
        end if;
    end case;

    if abort_i = '1' then
      rin.bus_state <= BUS_RESET;
      rin.state <= ST_READY;
    end if;      
    
  end process;

  moore : process (r)
  begin
    ready_o <= '0';
    failed_o <= '0';
    i2c_o.scl.drain_n <= '1';
    i2c_o.sda.drain_n <= '1';

    case r.bus_state is
      when BUS_OWNED =>
        owned_o <= '1';
        i2c_o.scl.drain_n <= '0';

      when others =>
        owned_o <= '0';
    end case;
    
    case r.state is
      when ST_RESET =>
        null;
        
      when ST_READY =>
        ready_o <= '1';
        
      when ST_FAILED =>
        failed_o <= '1';
        
      when ST_EXEC =>
        null;
        
      when ST_RESTART_PRE =>
        i2c_o.sda.drain_n <= '0';
        i2c_o.scl.drain_n <= '0';

      when ST_RESTART_SDA_RISE | ST_RESTART_SDA_HIGH =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '0';

      when ST_RESTART_SCL_RISE | ST_RESTART_SCL_HIGH =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '1';

      when ST_START_PRE =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '1';

      when ST_START_SDA_FALL | ST_START_SDA_LOW =>
        i2c_o.sda.drain_n <= '0';
        i2c_o.scl.drain_n <= '1';

      when ST_START_SCL_FALL | ST_START_SCL_LOW =>
        i2c_o.sda.drain_n <= '0';
        i2c_o.scl.drain_n <= '0';

      when ST_BYTE_PRE =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '0';

      when ST_BIT_SCL_RISE | ST_BIT_SCL_HIGH =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '1';

      when ST_BIT_SCL_FALL | ST_BIT_SCL_LOW =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '0';

      when ST_STOP_PRE =>
        i2c_o.sda.drain_n <= '0';
        i2c_o.scl.drain_n <= '0';

      when ST_STOP_SCL_RISE | ST_STOP_SCL_HIGH =>
        i2c_o.sda.drain_n <= '0';
        i2c_o.scl.drain_n <= '1';

      when ST_STOP_SDA_RISE | ST_STOP_SDA_HIGH =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '1';
    end case;
  end process;

end architecture;
