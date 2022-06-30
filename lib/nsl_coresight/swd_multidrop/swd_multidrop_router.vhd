library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, work;
use nsl_io.io.all;
use work.swd.all;
use work.swd_multidrop.all;
use work.dp.all;

entity swd_multidrop_router is
  generic(
    target_count_c: natural range 1 to 16;
    targetsel_base_c: std_ulogic_vector(27 downto 0)
    );
  port(
    reset_n_i: in std_ulogic;

    active_o: out std_ulogic;
    reset_o: out std_ulogic;
    selected_o: out std_ulogic;
    index_o: out natural range 0 to target_count_c-1;

    muxed_i: in swd_slave_i;
    muxed_o: out swd_slave_o;

    target_o: out swd_master_o_vector(0 to target_count_c-1);
    target_i: in swd_master_i_vector(0 to target_count_c-1)
    );
end entity;

architecture beh of swd_multidrop_router is
  
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

  type sel_state_t is (
    SEL_DEADEND,
    SEL_WAIT_TARGETSEL,
    SEL_WAIT_IDCODE,
    SEL_DONE
    );
  
  type regs_t is
  record
    state: state_t;
    sel_state: sel_state_t;
    index: natural range 0 to target_count_c-1;
    init_done: std_ulogic_vector(0 to target_count_c-1);

    dp_bank_sel: std_ulogic_vector(3 downto 0);
    left: integer range 0 to 31;
    cmd: std_ulogic_vector(3 downto 0);
    ack: std_ulogic_vector(2 downto 0);
    data: std_ulogic_vector(31 downto 0);
    par: std_ulogic;
    turn: integer range 0 to 3;
  end record;

  signal r, rin: regs_t;
  signal s_tech: work.dp.dp_tech_t;
  signal s_state: work.dp.dp_state_t;
  signal s_local_swdio: std_ulogic;
  signal s_master_drives, s_slave_drives: std_ulogic;
  
begin

  regs: process(muxed_i.clk, reset_n_i) is
  begin
    if rising_edge(muxed_i.clk) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.init_done <= (others => '0');
    end if;
  end process;

  transition: process(r, s_state, s_tech, muxed_i) is
    variable dio : std_ulogic;
  begin
    rin <= r;

    dio := to_x01(muxed_i.dio);
    
    case r.state is
      when ST_UNK =>
        rin.sel_state <= SEL_DEADEND;

      when ST_BAD_CMD =>
        if dio = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_RESET =>
        rin.index <= 0;
        rin.sel_state <= SEL_WAIT_TARGETSEL;
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
        rin.ack <= "-" & r.ack(2 downto 1);
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
              when "1100" => -- Write Targetsel
                if r.sel_state = SEL_WAIT_TARGETSEL then
                  if r.data(27 downto 0) = targetsel_base_c
                    and to_integer(unsigned(r.data(31 downto 28))) < target_count_c then
                    rin.sel_state <= SEL_WAIT_IDCODE;
                    rin.index <= to_integer(unsigned(r.data(31 downto 28)));
                  end if;
                else
                  rin.sel_state <= SEL_DEADEND;
                end if;
                
              when "1000" => -- Write Select
                if r.init_done(r.index) = '1' then
                  rin.dp_bank_sel <= r.data(3 downto 0);
                end if;

              when "0100" => -- Write DLCR
                if r.init_done(r.index) = '1'
                  and r.dp_bank_sel = x"1" then
                  rin.turn <= to_integer(unsigned(r.data(9 downto 8)));
                end if;

              when others =>
                null;
            end case;
          end if;
        else
          case r.cmd is
            when "0010" => -- Read IDCODE
              if r.sel_state = SEL_WAIT_IDCODE then
                rin.sel_state <= SEL_DONE;
                rin.init_done(r.index) <= '1';
              end if;

            when others =>
              null;
          end case;

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
      rin.init_done <= (others => '0');
    elsif s_state = DP_RESET then
      rin.state <= ST_RESET;
    end if;
  end process;

  local: process(r) is
  begin
    s_local_swdio <= '-';

    case r.state is
      when ST_ACK_TURN | ST_DATA_TURN | ST_CMD_TURN | ST_UNK =>
        s_slave_drives <= '0';
        s_master_drives <= '0';

      when ST_RESET | ST_IDLE | ST_CMD | ST_PAR | ST_STOP | ST_PARK | ST_BAD_CMD =>
        s_master_drives <= '1';
        s_slave_drives <= '0';

      when ST_ACK =>
        s_local_swdio <= r.ack(0);
        if r.cmd = "0010" or r.init_done(r.index) = '1' then
          s_slave_drives <= '1';
        else
          s_slave_drives <= '0';
        end if;
        s_master_drives <= '0';

      when ST_DATA =>
        if r.cmd = "0010" or r.init_done(r.index) = '1' then
          s_slave_drives <= r.cmd(1);
        else
          s_slave_drives <= '0';
        end if;
        s_master_drives <= not r.cmd(1);
        s_local_swdio <= r.data(0);
        
      when ST_DATA_PAR =>
        if r.cmd = "0010" or r.init_done(r.index) = '1' then
          s_slave_drives <= r.cmd(1);
        else
          s_slave_drives <= '0';
        end if;
        s_master_drives <= not r.cmd(1);
        s_local_swdio <= r.par;
    end case;
  end process;

  mealy: process(r, muxed_i, target_i, s_master_drives, s_slave_drives, s_local_swdio) is
  begin
    for i in target_o'range
    loop
      target_o(i).clk <= muxed_i.clk;
      target_o(i).dio.output <= '1';
      target_o(i).dio.v <= '1';
    end loop;

    case r.sel_state is
      when SEL_DEADEND | SEL_WAIT_TARGETSEL =>
        selected_o <= '0';
        muxed_o.dio <= directed_z;

      when SEL_WAIT_IDCODE | SEL_DONE =>
        selected_o <= '1';
        muxed_o.dio.v <= target_i(r.index).dio;
        muxed_o.dio.output <= s_slave_drives;
        target_o(r.index).clk <= muxed_i.clk;
        target_o(r.index).dio.output <= s_master_drives;
        target_o(r.index).dio.v <= muxed_i.dio;
    end case;
  end process;

  index_o <= r.index;
  active_o <= r.init_done(r.index);
  reset_o <= '1' when r.state = ST_RESET else '0';
  
  monitor: work.dp.dp_monitor
    port map(
      reset_n_i => reset_n_i,
      dp_i => muxed_i,

      tech_o => s_tech,
      state_o => s_state
      );
  
end architecture;
