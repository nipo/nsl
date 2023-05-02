library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, work;
use nsl_io.io.all;
use work.swd.all;
use work.dp.all;

entity swd_bridge is
  port(
    reset_n_i: in std_ulogic;

    probe_i: in swd_slave_i;
    probe_o: out swd_slave_o;

    target_o: out swd_master_o;
    target_i: in swd_master_i
    );
end entity;

architecture beh of swd_bridge is
  
  type state_t is (
    ST_UNK,
    ST_BAD_CMD,
    ST_RESET,
    ST_IDLE,
    ST_CMD,
    ST_PAR,
    ST_STOP,
    ST_PARK,
    ST_CMD_TURN,
    ST_ACK,
    ST_ACK_TURN,
    ST_DATA,
    ST_DATA_PAR,
    ST_DATA_TURN
    );
  
  type regs_t is
  record
    state: state_t;

    dp_bank_sel: std_ulogic_vector(3 downto 0);
    left: integer range 0 to 63;
    cmd: std_ulogic_vector(3 downto 0);
    data: std_ulogic_vector(31 downto 0);
    par: std_ulogic;
    turn: integer range 0 to 3;
  end record;

  signal r, rin: regs_t;
  signal s_tech: work.dp.dp_tech_t;
  signal s_state: work.dp.dp_state_t;
  signal s_master_drives, s_slave_drives: std_ulogic;
  
begin

  regs: process(probe_i.clk, reset_n_i) is
  begin
    if rising_edge(probe_i.clk) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_UNK;
    end if;
  end process;

  transition: process(r, s_state, s_tech, probe_i) is
    variable dio : std_ulogic;
  begin
    rin <= r;

    dio := to_x01(probe_i.dio);
    
    case r.state is
      when ST_UNK =>
        null;

      when ST_BAD_CMD =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        elsif dio = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_RESET =>
        rin.turn <= 0;
        rin.dp_bank_sel <= x"0";

        if dio = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_IDLE =>
        rin.cmd <= "----";
        if dio = '1' then
          rin.state <= ST_CMD;
          rin.left <= 3;
          rin.par <= '0';
        end if;
        
      when ST_CMD =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_PAR;
        end if;
        rin.cmd <= dio & r.cmd(3 downto 1);
        rin.par <= r.par xor dio;

      when ST_PAR =>
        rin.par <= r.par xor dio;
        rin.state <= ST_STOP;

      when ST_STOP =>
        if dio /= '0' or r.par /= '0' then
          rin.state <= ST_BAD_CMD;
          rin.left <= 32 + 1 + 3 + 2 - 1;
        else
          rin.state <= ST_PARK;
        end if;

      when ST_PARK =>
        rin.state <= ST_CMD_TURN;
        rin.left <= r.turn;

      when ST_CMD_TURN =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_ACK;
          rin.left <= 2;
        end if;

      when ST_ACK =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        elsif r.cmd(1) = '1' then
          rin.left <= 31;
          rin.state <= ST_DATA;
          rin.par <= '0';
        else
          rin.left <= r.turn;
          rin.state <= ST_ACK_TURN;
        end if;

      when ST_ACK_TURN =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.left <= 31;
          rin.state <= ST_DATA;
          rin.par <= '0';
        end if;

      when ST_DATA =>
        rin.data <= dio & r.data(31 downto 1);
        rin.par <= r.par xor dio;
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_DATA_PAR;
        end if;

      when ST_DATA_PAR =>
        if r.cmd(1) = '0' then
          rin.state <= ST_IDLE;
     
          if r.par = dio then
            case r.cmd is
              when "1000" => -- Write Select
                rin.dp_bank_sel <= r.data(3 downto 0);

              when "0100" => -- Write DLCR
                if r.dp_bank_sel = x"1" then
                  rin.turn <= to_integer(unsigned(r.data(9 downto 8)));
                end if;

              when others =>
                null;
            end case;
          end if;
        else
          rin.left <= r.turn;
          rin.state <= ST_DATA_TURN;
        end if;

      when ST_DATA_TURN =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.state <= ST_IDLE;
        end if;
    end case;

    if s_tech /= DP_TECH_SWD then
      rin.state <= ST_UNK;
    elsif s_state = DP_RESET then
      rin.state <= ST_RESET;
    end if;
  end process;

  local: process(r) is
  begin
    case r.state is
      when ST_ACK_TURN | ST_DATA_TURN | ST_CMD_TURN | ST_UNK | ST_BAD_CMD =>
        s_master_drives <= '1';
        s_slave_drives <= '0';

      when ST_RESET | ST_IDLE | ST_CMD | ST_PAR | ST_STOP | ST_PARK =>
        s_master_drives <= '1';
        s_slave_drives <= '0';

      when ST_ACK =>
        s_master_drives <= '0';
        s_slave_drives <= '1';

      when ST_DATA | ST_DATA_PAR =>
        s_master_drives <= not r.cmd(1);
        s_slave_drives <= r.cmd(1);
    end case;
  end process;

  probe_o.dio.v <= target_i.dio;
  probe_o.dio.output <= s_slave_drives;
  target_o.clk <= probe_i.clk;
  target_o.dio.output <= s_master_drives;
  target_o.dio.v <= probe_i.dio;
  
  monitor: work.dp.dp_monitor
    port map(
      reset_n_i => reset_n_i,
      dp_i => probe_i,

      tech_o => s_tech,
      state_o => s_state
      );
  
end architecture;
