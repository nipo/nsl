--  Copyright (c) 2016, Vincent Defilippi <vincentdefilippi@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

library util;

entity i2c_slave is
  port (
    p_clk: in std_ulogic;
    p_resetn: in std_ulogic;

    p_scl: in std_ulogic;
    p_sda: in std_ulogic;
    p_scl_drain: out std_ulogic;
    p_sda_drain: out std_ulogic;

    p_start: out std_ulogic;
    p_stop: out std_ulogic;

    p_rdata: in std_ulogic_vector(7 downto 0);
    p_read: out std_ulogic;

    p_wdata: out std_ulogic_vector(7 downto 0);
    p_wack: in std_ulogic;
    p_addr: out std_ulogic;
    p_write: out std_ulogic
  );
end i2c_slave;

architecture arch of i2c_slave is

  type state_type is (
    S_IDLE,
    S_READ,
    S_READ_CHECK_DATA,
    S_READ_WAIT_CHECK_ACK,
    S_READ_SEND_ACK,
    S_READ_DONE,
    S_WRITE_LOAD,
    S_WRITE,
    S_WRITE_RECV_ACK,
    S_WRITE_DONE
  );

  signal state: state_type := S_IDLE;

  signal scl_bin: std_ulogic;
  signal sda_bin: std_ulogic;

  signal scl_filt: std_ulogic;
  signal scL_rise: std_ulogic;
  signal scl_fall: std_ulogic;

  signal sda_filt: std_ulogic;
  signal sda_rise: std_ulogic;
  signal sda_fall: std_ulogic;

  signal start_s: std_ulogic;
  signal stop_s: std_ulogic;

  signal cnt: integer range 0 to 7 := 0;
  signal sreg: std_ulogic_vector(7 downto 0) := (others => '0');
  signal ack: std_ulogic := '1';

  signal addr: std_ulogic := '1';
  signal write: std_ulogic := '0';

begin

  scl_bin <= '0' when p_scl = '0' else '1';
  sda_bin <= '0' when p_sda = '0' else '1';

  scl_sync: util.sync.sync_input
    port map (
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_input => scl_bin,
      p_output => scl_filt,
      p_rise => scl_rise,
      p_fall => scl_fall
      );

  sda_sync: util.sync.sync_input
    port map (
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_input => sda_bin,
      p_output => sda_filt,
      p_rise => sda_rise,
      p_fall => sda_fall
      );

  start_s <= scl_filt and sda_fall;
  stop_s <= scl_filt and sda_rise;

  p_scl_drain <= '0';
  p_start <= start_s;
  p_stop <= stop_s;
  p_addr <= write and addr;
  p_write <= write and not addr;
  p_wdata <= sreg;

  process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      state <= S_IDLE;

    elsif (rising_edge(p_clk)) then
      if (stop_s = '1') then
        state <= S_IDLE;

      elsif (start_s = '1') then
        cnt <= 0;
        addr <= '1';
        state <= S_READ;

      else
        case state is
          when S_IDLE =>
            p_sda_drain <= '0';
            cnt <= 0;
            sreg <= (others => '0');
            addr <= '1';
            ack <= '1';
            write <= '0';
            p_read <= '0';

          when S_READ =>
            if scl_rise = '1' then
              sreg <= sreg(6 downto 0) & sda_filt;
              if cnt = 7 then
                state <= S_READ_CHECK_DATA;
              else
                cnt <= cnt + 1;
              end if;
            end if;

          when S_READ_CHECK_DATA =>
            write <= '1';
            state <= S_READ_WAIT_CHECK_ACK;

          when S_READ_WAIT_CHECK_ACK =>
            write <= '0';
            if p_wack = '1' then
              ack <= '0';
            end if;

            if scl_fall = '1' then
              state <= S_READ_SEND_ACK;
            end if;

          when S_READ_SEND_ACK =>
            if ack = '0' then
              p_sda_drain <= '1';
            end if;

            if scl_fall = '1' then
              state <= S_READ_DONE;
            end if;

          when S_READ_DONE =>
            ack <= '1';
            p_sda_drain <= '0';
            cnt <= 0;

            if ack = '1' then
              state <= S_IDLE;
            elsif addr = '1' then
              addr <= '0';

              if sreg(0) = '0' then
                state <= S_READ;
              else
                state <= S_WRITE_LOAD;
              end if;
            else
              state <= S_READ;
            end if;

          when S_WRITE_LOAD =>
            sreg <= p_rdata;
            p_read <= '1';
            state <= S_WRITE;

          when S_WRITE =>
            p_read <= '0';
            p_sda_drain <= '0';

            if sreg(7) = '0' then
              p_sda_drain <= '1';
            end if;

            if scl_fall = '1' then
              sreg <= sreg(6 downto 0) & '0';
              if cnt = 7 then
                state <= S_WRITE_RECV_ACK;
              else
                cnt <= cnt + 1;
              end if;
            end if;

          when S_WRITE_RECV_ACK =>
            p_sda_drain <= '0';
            if scl_rise = '1' then
              if p_sda = '0' then
                ack <= '0';
              end if;
              state <= S_WRITE_DONE;
            end if;

          when S_WRITE_DONE =>
            cnt <= 0;
            if scl_fall = '1' then
              ack <= '1';
              if ack = '0' then
                state <= S_WRITE_LOAD;
              else
                state <= S_IDLE;
              end if;
            end if;
        end case;
      end if;

    end if;
  end process;
end arch;


