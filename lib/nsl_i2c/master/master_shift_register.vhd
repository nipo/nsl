library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

entity master_shift_register is
  port(
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i;

    start_i : in std_ulogic;
    arb_ok_o : out std_ulogic;

    enable_i : in std_ulogic;
    send_mode_i : in std_ulogic;

    send_valid_i : in std_ulogic;
    send_ready_o : out std_ulogic;
    send_data_i : in std_ulogic_vector(7 downto 0);

    recv_valid_o : out std_ulogic;
    recv_ready_i : in std_ulogic;
    recv_data_o : out std_ulogic_vector(7 downto 0)
    );
end entity;

architecture beh of master_shift_register is

  type state_t is (
    ST_RESET,

    ST_ARB_LOST,

    ST_IDLE,
    ST_NEXT,

    -- Waiting data from commander
    ST_WORD_DATA_GET,

    -- Repeated 8x writing a word
    ST_WORD_SCL_RISE,
    ST_WORD_SCL_FALL,

    -- Putting data to commander
    ST_WORD_DATA_PUT,

    -- Waiting ack from commander
    ST_ACK_DATA_GET,

    -- Reading ack after a write
    ST_ACK_SCL_RISE,
    ST_ACK_SCL_FALL,

    -- Putting ack to commander
    ST_ACK_DATA_PUT
    );

  type regs_t is record
    state     : state_t;
    send_mode : std_ulogic;
    bit_count : natural range 0 to 7;
    shreg : std_ulogic_vector(8 downto 0);
  end record;

  signal r, rin : regs_t;

begin
  
  ck : process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition : process (i2c_i, r, start_i,
                        enable_i, send_mode_i,
                        send_valid_i, send_data_i,
                        recv_ready_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_ARB_LOST;

      when ST_ARB_LOST =>
        if enable_i = '0' then
          rin.state <= ST_IDLE;
        end if;
        
      when ST_IDLE =>
        if enable_i = '1' then
          rin.state <= ST_NEXT;
        end if;

      when ST_NEXT =>
        if enable_i = '0' then
          rin.state <= ST_IDLE;
        else
          rin.send_mode <= send_mode_i;
          rin.bit_count <= 7;
          rin.shreg <= (others => '1');
          if send_mode_i = '1' then
            rin.state <= ST_WORD_DATA_GET;
          else
            rin.state <= ST_WORD_SCL_RISE;
          end if;
        end if;

      when ST_WORD_DATA_GET =>
        if enable_i = '0' then
          rin.state <= ST_IDLE;
        elsif send_valid_i = '1' then
          rin.shreg <= send_data_i & "-";
          rin.state <= ST_WORD_SCL_RISE;
        end if;

      when ST_WORD_SCL_RISE =>
        if i2c_i.scl = '1' then
          rin.shreg(0) <= i2c_i.sda;
          if r.send_mode = '1'
            and i2c_i.sda = '0'
            and r.shreg(r.shreg'left) = '1' then
            rin.state <= ST_ARB_LOST;
          else
            rin.state <= ST_WORD_SCL_FALL;
          end if;
        end if;

      when ST_WORD_SCL_FALL =>
        if i2c_i.scl = '0' then
          rin.bit_count <= (r.bit_count - 1) mod 8;
          if r.bit_count /= 0 then
            rin.state <= ST_WORD_SCL_RISE;
            rin.shreg <= r.shreg(r.shreg'left-1 downto 0) & "-";
          elsif r.send_mode = '1' then
            -- We sent data, so we read ack from wire
            rin.state <= ST_ACK_SCL_RISE;
            rin.shreg <= (rin.shreg'left => '1', others => '-');
          else
            rin.state <= ST_WORD_DATA_PUT;
          end if;
        end if;

      when ST_WORD_DATA_PUT =>
        if recv_ready_i = '1' then
          rin.state <= ST_ACK_DATA_GET;
        end if;

      when ST_ACK_DATA_GET =>
        if send_valid_i = '1' then
          rin.shreg <= (rin.shreg'left => send_data_i(0), others => '-');
          rin.state <= ST_ACK_SCL_RISE;
        end if;

      when ST_ACK_SCL_RISE =>
        if i2c_i.scl = '1' then
          rin.shreg(0) <= i2c_i.sda;
          if r.send_mode = '0'
            and i2c_i.sda = '0'
            and r.shreg(r.shreg'left) = '1' then
            rin.state <= ST_ARB_LOST;
          else
            rin.state <= ST_ACK_SCL_FALL;
          end if;
        end if;

      when ST_ACK_SCL_FALL =>
        if i2c_i.scl = '0' then
          if enable_i = '0' then
            rin.state <= ST_IDLE;
          elsif r.send_mode = '1' then
            rin.state <= ST_ACK_DATA_PUT;
          else
            rin.state <= ST_NEXT;
          end if;
        end if;

      when ST_ACK_DATA_PUT =>
        if recv_ready_i = '1' then
          rin.state <= ST_NEXT;
        end if;
    end case;

    if start_i = '1' then
      if enable_i = '1' then
        rin.state <= ST_NEXT;
      else
--        rin.state <= ST_ARB_LOST;
      end if;
    end if;
  end process;

  moore : process (r)
  begin
    arb_ok_o <= '1';
    send_ready_o <= '0';
    recv_valid_o <= '0';
    recv_data_o <= r.shreg(7 downto 0);

    case r.state is
      when ST_RESET | ST_ARB_LOST =>
        arb_ok_o <= '0';
        
      when ST_WORD_DATA_GET | ST_ACK_DATA_GET => 
        send_ready_o <= '1';
        
      when ST_WORD_DATA_PUT | ST_ACK_DATA_PUT =>
        recv_valid_o <= '1';

      when others =>
        null;
    end case;

    case r.state is
      when ST_NEXT
        | ST_WORD_DATA_GET | ST_ACK_DATA_GET
        | ST_WORD_DATA_PUT | ST_ACK_DATA_PUT =>
        i2c_o.sda.drain_n <= r.shreg(r.shreg'left);
        i2c_o.scl.drain_n <= '0';

      when ST_WORD_SCL_RISE | ST_ACK_SCL_RISE
        | ST_WORD_SCL_FALL | ST_ACK_SCL_FALL =>
        i2c_o.sda.drain_n <= r.shreg(r.shreg'left);
        i2c_o.scl.drain_n <= '1';

      when others =>
        i2c_o.sda.drain_n <= '1';
        i2c_o.scl.drain_n <= '1';
    end case;
  end process;
  
end architecture;
