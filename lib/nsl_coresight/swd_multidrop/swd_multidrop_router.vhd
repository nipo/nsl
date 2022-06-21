library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
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
    index: natural range 0 to target_count_c-1;
    post_reset: std_ulogic;
    init_done: std_ulogic;
    selected: std_ulogic;
    txn_ok: std_ulogic;

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
  signal s_local: swd_slave_o;
  
begin

  regs: process(muxed_i.clk) is
  begin
    if rising_edge(muxed_i.clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_state, s_tech, muxed_i) is
    variable dio : std_ulogic;
  begin
    rin <= r;

    dio := to_x01(muxed_i.dio);
    
    case r.state is
      when ST_UNK =>
        null;

      when ST_RESET =>
        rin.post_reset <= '1';
        rin.init_done <= '0';
        rin.index <= 0;
        rin.selected <= '0';
        rin.turn <= 0;
        rin.dp_bank_sel <= x"0";

        if dio = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_IDLE =>
        rin.cmd <= "----";
        rin.txn_ok <= '0';
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
        rin.txn_ok <= r.par xnor dio;
        rin.state <= ST_STOP;

      when ST_STOP =>
        if dio /= '0' then
          rin.state <= ST_UNK;
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

          rin.post_reset <= '0';
          
          if r.par = dio then
            case r.cmd is
              when "1100" => -- Write Targetsel
                if r.post_reset = '1'
                  and r.selected = '0'
                  and r.data(27 downto 0) = targetsel_base_c
                  and r.init_done = '0'
                  and to_integer(unsigned(r.data(31 downto 28))) < target_count_c then
                  rin.selected <= '1';
                  rin.index <= to_integer(unsigned(r.data(31 downto 28)));
                  rin.post_reset <= '1';
                end if;

              when "1000" => -- Write Select
                if r.init_done = '1' then
                  rin.dp_bank_sel <= r.data(3 downto 0);
                end if;

              when "0100" => -- Write DLCR
                if r.init_done = '1'
                  and r.dp_bank_sel = x"1" then
                  rin.turn <= to_integer(unsigned(r.data(9 downto 8)));
                end if;

              when others =>
                null;
            end case;
          end if;
        else
          rin.post_reset <= '0';
          case r.cmd is
            when "0010" => -- Read IDCODE
              rin.init_done <= r.init_done or (r.post_reset and r.selected);

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
    elsif s_state = DP_RESET then
      rin.state <= ST_RESET;
    end if;
  end process;

  local: process(r) is
  begin
    s_local.dio.v <= '-';
    s_local.dio.output <= '0';

    if r.txn_ok = '1' then
      case r.state is
        when ST_UNK | ST_RESET | ST_IDLE | ST_CMD | ST_PAR | ST_STOP
          | ST_PARK | ST_ACK_TURN | ST_DATA_TURN | ST_CMD_TURN =>
          null;

        when ST_ACK =>
          s_local.dio.v <= r.ack(0);
          s_local.dio.output <= '1';

        when ST_DATA =>
          if r.cmd(1) = '1' then
            s_local.dio.v <= r.data(0);
            s_local.dio.output <= '1';
          end if;
          
        when ST_DATA_PAR =>
          if r.cmd(1) = '1' then
            s_local.dio.v <= r.par;
            s_local.dio.output <= '1';
          end if;
      end case;
    end if;
  end process;

  mealy: process(r, muxed_i, target_i, s_local) is
  begin
    target_o <= (others => (clk => muxed_i.clk, dio => (output => '1', v => '1')));

    if r.selected = '0' then
      muxed_o <= s_local;
    else
      muxed_o <= (dio => (output => '0', v => '-'));

      if s_local.dio.output = '1' then
        target_o(r.index).dio.output <= '0';
        target_o(r.index).dio.v <= '-';
        muxed_o.dio.output <= '1';
        muxed_o.dio.v <= target_i(r.index).dio;
      else
        target_o(r.index).dio.output <= '1';
        target_o(r.index).dio.v <= muxed_i.dio;
        muxed_o.dio.output <= '0';
        muxed_o.dio.v <= '-';
      end if;
    end if;
  end process;

  index_o <= r.index;
  selected_o <= r.selected;
  active_o <= r.init_done;
  reset_o <= '1' when r.state = ST_RESET else '0';
  
  monitor: work.dp.dp_monitor
    port map(
      reset_n_i => reset_n_i,
      dp_i => muxed_i,

      tech_o => s_tech,
      state_o => s_state
      );
  
end architecture;
