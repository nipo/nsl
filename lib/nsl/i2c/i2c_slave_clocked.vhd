library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, signalling;

entity i2c_slave_clocked is
  generic (
    clock_freq_c : natural := 100000000
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    address_i : in unsigned(7 downto 1);

    i2c_o  : out signalling.i2c.i2c_o;
    i2c_i  : in  signalling.i2c.i2c_i;

    start_o: out std_ulogic;
    stop_o: out std_ulogic;
    selected_o: out std_ulogic;

    error_i: in std_ulogic := '0';

    r_data_i: in std_ulogic_vector(7 downto 0);
    r_ready_o: out std_ulogic;
    r_valid_i: in std_ulogic := '1';

    w_data_o: out std_ulogic_vector(7 downto 0);
    w_valid_o: out std_ulogic;
    w_ready_i: in std_ulogic := '1'
  );
end i2c_slave_clocked;

architecture arch of i2c_slave_clocked is

  constant debouncer_delay : natural := 2;

  type state_t is (
    ST_BUSY,
    ST_STOPPED,
    ST_ADDR,
    ST_ADDR_DONE,
    ST_ADDR_ACK,
    ST_WRITE_SHIFT,
    ST_WRITE_WAIT,
    ST_WRITE_ACK,
    ST_READ_WAIT,
    ST_READ_SHIFT,
    ST_READ_ACK
    );

  signal scl: std_ulogic;
  signal sda: std_ulogic;

  signal scl_rise: std_ulogic;
  signal scl_fall: std_ulogic;

  signal sda_rise: std_ulogic;
  signal sda_fall: std_ulogic;
  
  type regs_t is
  record
    state : state_t;
    shreg : std_ulogic_vector(7 downto 0);
    bit_left : natural range 0 to 7;
  end record;

  signal s_i2c_i : signalling.i2c.i2c_i;
  signal s_start, s_stop : boolean;
  signal r, rin : regs_t;

begin

  s_i2c_i.sda.v <= to_x01(i2c_i.sda.v);
  s_i2c_i.scl.v <= to_x01(i2c_i.scl.v);

  sda_sync: util.sync.sync_input
    generic map(
      N => debouncer_delay
      )
    port map(
      p_clk => clock_i,
      p_resetn => reset_n_i,
      p_input => s_i2c_i.sda.v,
      p_output => sda,
      p_rise => sda_rise,
      p_fall => sda_fall
      );

  scl_sync: util.sync.sync_input
    generic map(
      N => debouncer_delay
      )
    port map (
      p_clk => clock_i,
      p_resetn => reset_n_i,
      p_input => s_i2c_i.scl.v,
      p_output => scl,
      p_rise => scl_rise,
      p_fall => scl_fall
      );

  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_BUSY;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  s_start <= scl = '1' and sda_fall = '1';
  s_stop <= scl = '1' and sda_rise = '1';

  fsm: process(scl, scl_rise, scl_fall, sda, sda_rise, sda_fall,
               r, address_i,
               error_i, r_data_i, r_valid_i, w_ready_i)
  begin
    rin <= r;

    if error_i = '1' then
      rin.state <= ST_BUSY;
    elsif s_start then
      rin.state <= ST_ADDR;
      rin.shreg <= (others => '-');
      rin.bit_left <= 7;
    elsif s_stop then
      rin.state <= ST_STOPPED;
    else
      case r.state is
        when ST_ADDR =>
          if scl_rise = '1' then
            rin.shreg <= r.shreg(6 downto 0) & sda;

            rin.bit_left <= (r.bit_left - 1) mod 8;
            if r.bit_left = 0 then
              rin.state <= ST_ADDR_DONE;
            end if;
          end if;

        when ST_ADDR_DONE =>
          if r.shreg(7 downto 1) /= std_ulogic_vector(address_i) then
            rin.state <= ST_BUSY;
          elsif scl_fall = '1' then
            rin.state <= ST_ADDR_ACK;
          end if;

        when ST_ADDR_ACK =>
          if scl_fall = '1' then
            if r.shreg(0) = '1' then
              rin.state <= ST_READ_WAIT;
            else
              rin.bit_left <= 7;
              rin.shreg <= (others => '-');
              rin.state <= ST_WRITE_SHIFT;
            end if;
          end if;

        when ST_WRITE_SHIFT =>
          if scl_fall = '1' then
            rin.bit_left <= (r.bit_left - 1) mod 8;
            if r.bit_left = 0 then
              rin.state <= ST_WRITE_WAIT;
            end if;
          end if;

          if scl_rise = '1' then
            rin.shreg <= r.shreg(6 downto 0) & sda;
          end if;

        when ST_WRITE_WAIT =>
          if w_ready_i = '1' then
            rin.state <= ST_WRITE_ACK;
            rin.bit_left <= 7;
          end if;

        when ST_WRITE_ACK =>
          if scl_fall = '1' then
            rin.bit_left <= 7;
            rin.shreg <= (others => '-');
            rin.state <= ST_WRITE_SHIFT;
          end if;

        when ST_READ_SHIFT =>
          if scl_fall = '1' then
            rin.bit_left <= (r.bit_left - 1) mod 8;
            rin.shreg <= r.shreg(6 downto 0) & '-';
            if r.bit_left = 0 then
              rin.state <= ST_READ_ACK;
            end if;
          end if;

        when ST_READ_ACK =>
          if scl_rise = '1' then
            if sda = '1' then
              rin.state <= ST_BUSY;
            end if;
          end if;

          if scl_fall = '1' then
            rin.state <= ST_READ_WAIT;
          end if;

        when ST_READ_WAIT =>
          if r_valid_i = '1' then
            rin.state <= ST_READ_SHIFT;
            rin.shreg <= r_data_i;
            rin.bit_left <= 7;
          end if;

        when ST_BUSY | ST_STOPPED =>
          null;
      end case;
    end if;
  end process;

  w_data_o <= r.shreg;
  stop_o <= '1' when s_stop else '0';
  start_o <= '1' when s_start else '0';
  
  moore: process(r)
  begin
    i2c_o.scl.drain <= '0';
    i2c_o.sda.drain <= '0';
    selected_o <= '1';
    w_valid_o <= '0';
    r_ready_o <= '0';

    case r.state is
      when ST_READ_WAIT =>
        i2c_o.scl.drain <= '1';
        r_ready_o <= '1';

      when ST_WRITE_WAIT =>
        i2c_o.scl.drain <= '1';
        w_valid_o <= '1';

      when ST_READ_SHIFT =>
        i2c_o.sda.drain <= not r.shreg(7);

      when ST_WRITE_ACK =>
        i2c_o.sda.drain <= '1';

      when ST_ADDR_ACK =>
        i2c_o.sda.drain <= '1';

      when ST_BUSY | ST_STOPPED | ST_ADDR | ST_ADDR_DONE =>
        selected_o <= '0';
        
      when others =>
        null;
    end case;
  end process;
  
end arch;
