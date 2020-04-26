library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

entity clockfree_slave is
  port (
    reset_n_i : in  std_ulogic := '1';
    clock_o   : out std_ulogic;

    slave_address_c : in unsigned(7 downto 1);

    i2c_o : out nsl_i2c.i2c.i2c_o;
    i2c_i : in  nsl_i2c.i2c.i2c_i;

    start_o    : out std_ulogic;
    stop_o     : out std_ulogic;
    selected_o : out std_ulogic;

    error_i : in std_ulogic := '0';

    read_data_i   : in  std_ulogic_vector(7 downto 0);
    read_strobe_o : out std_ulogic;
    read_ready_i  : in  std_ulogic := '1';

    write_data_o   : out std_ulogic_vector(7 downto 0);
    write_strobe_o : out std_ulogic;
    write_ready_i  : in  std_ulogic := '1'
  );
end clockfree_slave;

architecture arch of clockfree_slave is

  signal start, stop : boolean;
  
  type state_t is (
    ST_STOPPED,
    ST_NOT_SELECTED,
    ST_ADDR,
    ST_ADDR_ACK,
    ST_WRITE_DATA,
    ST_WRITE_ACK,
    ST_READ_DATA,
    ST_READ_ACK
    );

  type regs_t is
  record
    state       : state_t;
    shreg       : std_ulogic_vector(7 downto 0);
    read        : std_ulogic;
    bit_left    : natural range 0 to 7;
    start_ack   : boolean;
    stop_ack    : boolean;
    can_stretch : boolean;
  end record;

  signal s_i2c_i : nsl_i2c.i2c.i2c_i;

  signal r, rin : regs_t;

--  attribute mark_debug : string;
--  attribute mark_debug of r : signal is "TRUE";

begin

  s_i2c_i.sda <= to_x01(i2c_i.sda);
  s_i2c_i.scl <= to_x01(i2c_i.scl);

  start_detect : process(s_i2c_i.sda, r.start_ack)
  begin
    if r.start_ack then
      start <= false;
    elsif falling_edge(s_i2c_i.sda) then
      start <= start or s_i2c_i.scl = '1';
    end if;
  end process;

  stop_detect : process(s_i2c_i.sda, r.stop_ack)
  begin
    if r.stop_ack then
      stop <= false;
    elsif rising_edge(s_i2c_i.sda) then
      stop <= stop or s_i2c_i.scl = '1';
    end if;
  end process;

  regs : process(s_i2c_i.scl, reset_n_i)
  begin
    if s_i2c_i.scl = '0' then
      r.can_stretch <= true;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_NOT_SELECTED;
    elsif rising_edge(s_i2c_i.scl) then
      r <= rin;
    end if;
  end process;

  fsm : process(s_i2c_i.sda, start, stop, r, error_i, read_data_i, slave_address_c)
  begin
    rin <= r;

    rin.start_ack   <= start;
    rin.stop_ack    <= stop;
    rin.can_stretch <= false;

    rin.read <= '0';

    if start then
      rin.state    <= ST_ADDR;
      rin.bit_left <= 6;
      rin.shreg    <= "-------" & s_i2c_i.sda;
    elsif stop then
      rin.state <= ST_STOPPED;
    else
      case r.state is
        when ST_STOPPED | ST_NOT_SELECTED =>
          null;
          
        when ST_ADDR =>
          rin.shreg    <= r.shreg(6 downto 0) & s_i2c_i.sda;
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            if r.shreg(6 downto 0) /= std_ulogic_vector(slave_address_c) then
              rin.state <= ST_NOT_SELECTED;
            else
              rin.state <= ST_ADDR_ACK;
            end if;
          end if;

        when ST_ADDR_ACK =>
          rin.shreg <= (others => '-');
          if error_i = '1' or r.shreg(7 downto 1) /= std_ulogic_vector(slave_address_c) then
            rin.state <= ST_NOT_SELECTED;
          elsif r.shreg(0) = '1' then
            rin.state <= ST_READ_DATA;
            rin.read  <= '1';
          else
            rin.state <= ST_WRITE_DATA;
          end if;
          
        when ST_WRITE_DATA =>
          rin.shreg    <= r.shreg(6 downto 0) & s_i2c_i.sda;
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            rin.state <= ST_WRITE_ACK;
          end if;

        when ST_READ_DATA =>
          if r.bit_left = 7 then
            rin.shreg <= read_data_i(6 downto 0) & '-';
          else
            rin.shreg <= r.shreg(6 downto 0) & '-';
          end if;
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            rin.state <= ST_READ_ACK;
          end if;

        when ST_WRITE_ACK =>
          rin.state <= ST_WRITE_DATA;

        when ST_READ_ACK =>
          rin.state <= ST_READ_DATA;
          if s_i2c_i.sda = '0' then
            rin.read <= '1';
          else
            rin.shreg <= (others => '-');
            rin.state <= ST_NOT_SELECTED;
          end if;
      end case;
    end if;
  end process;

  clock_o      <= s_i2c_i.scl;
  write_data_o <= r.shreg;
  stop_o       <= '1' when stop  else '0';
  start_o      <= '1' when start else '0';

  mealy : process(r, read_ready_i, write_ready_i, error_i, s_i2c_i.scl, read_data_i)
  begin
    if falling_edge(s_i2c_i.scl) then
      i2c_o.sda.drain_n <= '1';
      case r.state is
        when ST_READ_DATA =>
          if r.bit_left = 7 then
            i2c_o.sda.drain_n <= read_data_i(7);
          else
            i2c_o.sda.drain_n <= r.shreg(7);
          end if;

        when ST_ADDR_ACK | ST_WRITE_ACK =>
          if error_i = '0' then
            i2c_o.sda.drain_n <= '0';
          end if;

        when others =>
      end case;
    end if;

    i2c_o.scl.drain_n <= '1';

    if r.can_stretch then
      case r.state is
        when ST_READ_DATA =>
          i2c_o.scl.drain_n <= not r.read or read_ready_i;

        when ST_WRITE_ACK =>
          i2c_o.scl.drain_n <= write_ready_i;

        when others =>
          null;
      end case;
    end if;

    selected_o     <= '0';
    write_strobe_o <= '0';

    case r.state is
      when ST_ADDR_ACK =>
        selected_o <= '1';

      when ST_WRITE_ACK =>
        write_strobe_o <= '1';

      when others =>
        null;
    end case;

  end process;

  read_strobe_o <= r.read;
  
end arch;
