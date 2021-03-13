library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_math;

entity clocked_memory_controller is
  generic (
    addr_bytes: integer range 1 to 4 := 2;
    data_bytes: integer range 1 to 4 := 1
  );
  port (
    reset_n_i : in std_ulogic := '1';
    clock_i : in std_ulogic;

    slave_address_i: in unsigned(7 downto 1);

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i;

    start_o    : out std_ulogic;
    stop_o     : out std_ulogic;
    selected_o : out std_ulogic;

    addr_o     : out unsigned(addr_bytes*8-1 downto 0);

    r_ready_o  : out std_ulogic;
    r_data_i   : in  std_ulogic_vector(data_bytes*8-1 downto 0);
    r_valid_i  : in  std_ulogic := '1';

    w_valid_o  : out std_ulogic;
    w_data_o   : out std_ulogic_vector(data_bytes*8-1 downto 0);
    w_ready_i  : in  std_ulogic := '1'
    );
end clocked_memory_controller;

architecture arch of clocked_memory_controller is

  type state_t is (
    ST_RESET,
    ST_ADDRESS,
    ST_I2C_WAIT,
    ST_WRITE_WAIT,
    ST_READ_WAIT
    );

  type regs_t is
  record
    state : state_t;
    addr : unsigned(addr_bytes*8-1 downto 0);
    data : std_ulogic_vector(data_bytes*8-1 downto 0);
    data_valid : boolean;
    addr_byte_left : integer range 0 to addr_bytes-1;
  end record;

  constant data_bytes_l2 : natural := nsl_math.arith.log2(data_bytes);
  constant addr_lsb0 : unsigned(data_bytes_l2-1 downto 0) := (others => '0');

  signal r, rin: regs_t;
  signal s_start, s_stop : std_ulogic;
  signal s_r_valid, s_r_ready, s_w_ready, s_w_valid : std_ulogic;
  signal s_r_data, s_w_data : std_ulogic_vector(7 downto 0);

begin
  
  slave: nsl_i2c.clocked.clocked_slave
    port map (
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      address_i => slave_address_i,
      
      i2c_i => i2c_i,
      i2c_o => i2c_o,

      start_o => s_start,
      stop_o => s_stop,
      selected_o => selected_o,

      r_ready_o => s_r_ready,
      r_data_i => s_r_data,
      r_valid_i => s_r_valid,

      w_valid_o => s_w_valid,
      w_data_o => s_w_data,
      w_ready_i => s_w_ready
    );

  start_o <= s_start;
  stop_o <= s_stop;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, s_start, s_stop,
                      s_r_ready,
                      w_ready_i, r_valid_i, r_data_i,
                      s_w_data, s_w_valid)
    variable byte_off : integer range 0 to data_bytes - 1;
  begin
    rin <= r;

    byte_off := to_integer(r.addr) mod data_bytes;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_ADDRESS;
        rin.addr_byte_left <= addr_bytes - 1;

      when ST_ADDRESS =>
        if s_r_ready = '1' then
          rin.state <= ST_I2C_WAIT;
        end if;

        if s_w_valid = '1' then
          rin.addr(r.addr_byte_left*8+7 downto r.addr_byte_left*8) <= unsigned(s_w_data);
          if r.addr_byte_left = 0 then
            rin.state <= ST_I2C_WAIT;
          else
            rin.addr_byte_left <= r.addr_byte_left - 1;
          end if;
        end if;

      when ST_I2C_WAIT =>
        if s_w_valid = '1' then
          rin.data(byte_off*8+7 downto byte_off*8) <= s_w_data;
          if byte_off = data_bytes - 1 then
            rin.state <= ST_WRITE_WAIT;
          else
            rin.addr <= r.addr + 1;
          end if;
        elsif s_r_ready = '1' then
          if not r.data_valid then
            rin.state <= ST_READ_WAIT;
          else
            if byte_off = 0 then
              rin.data_valid <= false;
            end if;
            rin.addr <= r.addr + 1;
          end if;
        end if;

      when ST_WRITE_WAIT =>
        if w_ready_i = '1' then
          rin.state <= ST_I2C_WAIT;
          rin.addr <= r.addr + 1;
        end if;

      when ST_READ_WAIT =>
        if r_valid_i = '1' then
          rin.data_valid <= true;
          rin.data <= r_data_i;
          rin.state <= ST_I2C_WAIT;
        end if;
    end case;

    if s_stop = '1' or s_start = '1' then
      rin.state <= ST_RESET;
    end if;
  end process;

  addr_o <= r.addr(r.addr'left downto data_bytes_l2) & addr_lsb0;

  moore: process(r)
    variable byte_off : integer range 0 to data_bytes - 1;
  begin
    byte_off := to_integer(r.addr) mod data_bytes;

    s_w_ready <= '0';
    s_r_valid <= '0';
    w_data_o <= r.data;
    w_valid_o <= '0';
    r_ready_o <= '0';

    s_r_data <= r.data(byte_off*8+7 downto byte_off*8);

    case r.state is
      when ST_ADDRESS =>
        s_w_ready <= '1';

      when ST_I2C_WAIT =>
        s_w_ready <= '1';
        if r.data_valid then
          s_r_valid <= '1';
        end if;

      when ST_WRITE_WAIT =>
        w_valid_o <= '1';

      when ST_READ_WAIT =>
        r_ready_o <= '1';

      when others =>
        null;
    end case;
  end process;

end arch;
