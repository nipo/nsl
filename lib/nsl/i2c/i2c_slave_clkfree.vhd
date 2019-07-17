library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, signalling;

entity i2c_slave_clkfree is
  port (
    p_resetn : in std_ulogic := '1';
    p_clk_out : out std_ulogic;

    address : in unsigned(7 downto 1);

    p_i2c_o  : out signalling.i2c.i2c_o;
    p_i2c_i  : in  signalling.i2c.i2c_i;

    p_start: out std_ulogic;
    p_stop: out std_ulogic;
    p_selected: out std_ulogic;

    p_error: in std_ulogic := '0';

    p_r_data: in std_ulogic_vector(7 downto 0);
    p_r_strobe: out std_ulogic;
    p_r_ready: in std_ulogic := '1';

    p_w_data: out std_ulogic_vector(7 downto 0);
    p_w_strobe: out std_ulogic;
    p_w_ready: in std_ulogic := '1'
  );
end i2c_slave_clkfree;

architecture arch of i2c_slave_clkfree is

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
    state : state_t;
    shreg : std_ulogic_vector(7 downto 0);
    bit_left : natural range 0 to 7;
    start_ack : boolean;
    stop_ack : boolean;
    can_stretch : boolean;
  end record;

  signal r, rin : regs_t;

--  attribute mark_debug : string;
--  attribute mark_debug of r : signal is "TRUE";

begin
  
  start_detect: process(p_i2c_i.sda.v, r.start_ack)
  begin
    if r.start_ack then
      start <= false;
    elsif falling_edge(p_i2c_i.sda.v) then
      start <= p_i2c_i.scl.v = '1';
    end if;
  end process;

  stop_detect: process(p_i2c_i.sda.v, r.stop_ack)
  begin
    if r.stop_ack then
      stop <= false;
    elsif rising_edge(p_i2c_i.sda.v) then
      stop <= p_i2c_i.scl.v = '1';
    end if;
  end process;

  regs: process(p_i2c_i.scl.v, p_resetn)
  begin
    if p_i2c_i.scl.v = '0' then
      r.can_stretch <= true;
    end if;

    if p_resetn = '0' then
      r.state <= ST_NOT_SELECTED;
    elsif rising_edge(p_i2c_i.scl.v) then
      r <= rin;
    end if;
  end process;
  
  fsm: process(p_i2c_i.sda.v, start, stop, r, p_error, p_r_data, address)
  begin
    rin <= r;

    rin.start_ack <= start;
    rin.stop_ack <= stop;
    rin.can_stretch <= false;

    if start then
      rin.state <= ST_ADDR;
      rin.bit_left <= 6;
      rin.shreg <= "-------" & p_i2c_i.sda.v;
    elsif stop then
      rin.state <= ST_STOPPED;
    else
      case r.state is
        when ST_STOPPED | ST_NOT_SELECTED =>
          null;
          
        when ST_ADDR =>
          rin.shreg <= r.shreg(6 downto 0) & p_i2c_i.sda.v;
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            if r.shreg(6 downto 0) /= std_ulogic_vector(address) then
              rin.state <= ST_NOT_SELECTED;
            else
              rin.state <= ST_ADDR_ACK;
            end if;
          end if;

        when ST_ADDR_ACK =>
          if p_error = '1' or r.shreg(7 downto 1) /= address then
            rin.shreg <= (others => '-');
            rin.state <= ST_NOT_SELECTED;
          elsif r.shreg(0) = '1' then
            rin.state <= ST_READ_DATA;
            rin.shreg <= p_r_data;
          else
            rin.shreg <= (others => '-');
            rin.state <= ST_WRITE_DATA;
          end if;
          
        when ST_WRITE_DATA =>
          rin.shreg <= r.shreg(6 downto 0) & p_i2c_i.sda.v;
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            rin.state <= ST_WRITE_ACK;
          end if;

        when ST_READ_DATA =>
          rin.shreg <= r.shreg(6 downto 0) & '-';
          rin.bit_left <= (r.bit_left - 1) mod 8;
          if r.bit_left = 0 then
            rin.state <= ST_READ_ACK;
          end if;

        when ST_WRITE_ACK =>
          rin.state <= ST_WRITE_DATA;

        when ST_READ_ACK =>
          rin.state <= ST_READ_DATA;
          if p_i2c_i.sda.v = '0' then
            rin.shreg <= p_r_data;
          else
            rin.shreg <= (others => '-');
            rin.state <= ST_NOT_SELECTED;
          end if;
      end case;
    end if;
  end process;

  p_clk_out <= p_i2c_i.scl.v;
  p_w_data <= r.shreg;
  p_stop <= '1' when stop else '0';
  p_start <= '1' when start else '0';
  
  mealy: process(r, p_r_ready, p_w_ready, p_error, p_i2c_i.scl.v, p_i2c_i.sda.v)
  begin
    if falling_edge(p_i2c_i.scl.v) then
      p_i2c_o.sda.drain <= '0';
      case r.state is
        when ST_READ_DATA =>
          if r.shreg(7) = '0' then
            p_i2c_o.sda.drain <= '1';
          end if;

        when ST_ADDR_ACK | ST_WRITE_ACK =>
          if p_error = '0' then
            p_i2c_o.sda.drain <= '1';
          end if;

        when others =>
      end case;
    end if;

    p_i2c_o.scl.drain <= '0';

    if r.can_stretch then
      case r.state is
        when ST_ADDR_ACK =>
          if r.shreg(0) = '0' then
            p_i2c_o.scl.drain <= not p_w_ready;
          else
            p_i2c_o.scl.drain <= not p_r_ready;
          end if;

        when ST_READ_ACK =>
          p_i2c_o.scl.drain <= not p_r_ready;

        when ST_WRITE_ACK =>
          p_i2c_o.scl.drain <= not p_w_ready;

        when others =>
          null;
      end case;
    end if;

    p_selected <= '0';
    p_w_strobe <= '0';
    p_r_strobe <= '0';

    case r.state is
      when ST_ADDR_ACK =>
        p_selected <= '1';
        if r.shreg(0) = '1' then
          p_r_strobe <= '1';
        end if;

      when ST_READ_ACK =>
        p_r_strobe <= not p_i2c_i.sda.v;

      when ST_WRITE_ACK =>
        p_w_strobe <= '1';

      when others =>
        null;
    end case;

  end process;
  
end arch;
