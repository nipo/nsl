library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

entity swdp is
  generic(
    idr : unsigned(31 downto 0) := X"0ba00477"
    );
  port(
    swd_i : in nsl_coresight.swd.swd_slave_i;
    swd_o : out nsl_coresight.swd.swd_slave_o;
    
    dap_i : in nsl_coresight.dapbus.dapbus_m_i;
    dap_o : out nsl_coresight.dapbus.dapbus_m_o;

    ctrl_o : out std_ulogic_vector(31 downto 0);
    stat_i : in std_ulogic_vector(31 downto 0);

    abort_o : out std_ulogic_vector(4 downto 0)
    );
end entity swdp;

architecture beh of swdp is

  type sw_state_t is (
    SW_RESET,
    SW_BAD,
    SW_IDLE,
    SW_CMD_APNDP,
    SW_CMD_RNW,
    SW_CMD_A0,
    SW_CMD_A1,
    SW_CMD_PAR,
    SW_CMD_STOP,
    SW_CMD_PARK,
    SW_CMD_TURN,
    SW_ACK_OK,
    SW_ACK_WAIT,
    SW_ACK_FAULT,
    SW_ACK_TURN,
    SW_DATA,
    SW_DATA_PAR,
    SW_DATA_TURN
    );

  type ap_op_t is (
    AP_IDLE,
    AP_READ,
    AP_WRITE,
    AP_ABORT,
    AP_ERROR
    );

  type ack_state_t is (
    ACK_OK,
    ACK_WAIT,
    ACK_FAULT
    );
  
  type regs_t is record
    a : unsigned(1 downto 0);
    rnw : std_logic;

    ready : std_ulogic;
    apndp : std_ulogic;
    
    count : integer range 0 to 31;
    turnaround : natural range 0 to 3;
    ap_sel: unsigned(7 downto 0);
    ap_bank_sel: unsigned(3 downto 0);
    dp_bank_sel: unsigned(3 downto 0);

    sw_state : sw_state_t;
    data : unsigned(31 downto 0);
    data_par : std_logic;
    ack_state : ack_state_t;

    ap_state : ap_op_t;
    ap_addr : unsigned(15 downto 2);
    ap_wdata : unsigned(31 downto 0);
    ap_rdbuf : unsigned(31 downto 0);

    ctrl : unsigned(31 downto 0);
  end record;
  signal r_reset_counter : natural range 0 to 49;

  signal r, rin: regs_t;
  
  function boolean_to_logic(B : Boolean) return std_ulogic is
  begin
    if B then
      return '1';
    else
      return '0';
    end if;
  end function;
begin
  reg: process (swd_i.clk) is
  begin
    if swd_i.clk = '1' and swd_i.clk'event then
      if to_x01(swd_i.dio) = '1' and r_reset_counter = 0 then
        r.sw_state <= SW_RESET;
      else
        r <= rin;
        if to_x01(swd_i.dio) = '0' then
          r_reset_counter <= 49;
        elsif r_reset_counter /= 0 then
          r_reset_counter <= r_reset_counter - 1;
        end if;
      end if;
    end if;
  end process;

  fsm: process(r, swd_i.dio, dap_i, stat_i)
    variable swdio : std_ulogic;
  begin
    rin <= r;

    swdio := to_x01(swd_i.dio);
    
    case r.sw_state is
      when SW_RESET =>
        rin.sw_state <= SW_IDLE;
        rin.turnaround <= 0;
        rin.ap_rdbuf <= (others => '-');
        rin.data <= (others => '-');
        rin.ap_bank_sel <= (others => '0');
        rin.ap_sel <= (others => '0');
        rin.dp_bank_sel <= (others => '0');
        rin.a <= (others => '0');
        rin.ready <= '0';

      when SW_BAD =>
        if r.count /= 0 then
          rin.count <= r.count - 1;
        else
          rin.sw_state <= SW_IDLE;
        end if;
        
      when SW_IDLE =>
        rin.data_par <= '1';
        if swdio = '1' then
          rin.sw_state <= SW_CMD_APNDP;
        end if;

      when SW_CMD_APNDP =>
        rin.apndp <= swdio;
        rin.data_par <= r.data_par xor swdio;
        rin.sw_state <= SW_CMD_RNW;

      when SW_CMD_RNW =>
        rin.rnw <= swdio;
        rin.data_par <= r.data_par xor swdio;
        rin.sw_state <= SW_CMD_A0;

      when SW_CMD_A0 =>
        rin.a(0) <= swdio;
        rin.data_par <= r.data_par xor swdio;
        rin.sw_state <= SW_CMD_A1;

      when SW_CMD_A1 =>
        rin.a(1) <= swdio;
        rin.data_par <= r.data_par xor swdio;
        rin.sw_state <= SW_CMD_PAR;

      when SW_CMD_PAR =>
        rin.sw_state <= SW_CMD_STOP;
        rin.data_par <= r.data_par xor swdio;

      when SW_CMD_STOP =>
        rin.data_par <= r.data_par and not swdio;
        rin.sw_state <= SW_CMD_PARK;

      when SW_CMD_PARK =>
        if r.data_par = '0' then
          rin.sw_state <= SW_BAD;
          rin.count <= 31;
        else
          rin.ack_state <= ACK_OK;

          if r.rnw = '1' then
            if r.apndp = '0' then
              -- DP Read
              rin.data <= (others => '-');
              case r.a is
                when "00" => -- IDR
                  rin.data <= idr;

                when "01" => -- Banked
                  case r.dp_bank_sel is
                    when "0000" => -- CTRL/Stat
                      rin.data <= unsigned(stat_i);
                      
                    when "0001" => -- DLCR
                      rin.data(9 downto 8) <= to_unsigned(rin.turnaround, 2);
                      rin.data(7 downto 0) <= X"43";

                    when others =>
                      null;
                  end case;
                  
                when "10" => -- Select
                  null;
                  
                when "11" => -- RdBuf
                  rin.data <= r.ap_rdbuf;

                when others =>
                  null;
              end case;
            else
              -- AP Read
              rin.data <= r.ap_rdbuf;
            end if;
          end if;

          if r.apndp = '1' then
            -- Any AP access
            case r.ap_state is
              when AP_IDLE =>
                rin.ap_addr <= r.ap_sel & r.ap_bank_sel & r.a;
                if r.rnw = '1' then
                  rin.ap_state <= AP_READ;
                end if;
                rin.ack_state <= ACK_OK;

              when AP_ERROR =>
                rin.ack_state <= ACK_FAULT;

              when others =>
                rin.ack_state <= ACK_WAIT;
            end case;
          end if;

          rin.sw_state <= SW_CMD_TURN;
          rin.count <= r.turnaround;
        end if;

      when SW_CMD_TURN =>
        rin.count <= (r.count - 1) mod 32;

        if r.count = 0 then
          rin.sw_state <= SW_ACK_OK;
        end if;

      when SW_ACK_OK =>
        rin.sw_state <= SW_ACK_WAIT;

      when SW_ACK_WAIT =>
        rin.sw_state <= SW_ACK_FAULT;
          
      when SW_ACK_FAULT =>
        if r.ack_state = ACK_OK then
          if r.rnw = '1' then
            rin.data_par <= '0';
            rin.sw_state <= SW_DATA;
            rin.count <= 31;
          else
            rin.sw_state <= SW_ACK_TURN;
            rin.count <= r.turnaround;
          end if;
        else
          rin.sw_state <= SW_IDLE;
        end if;

      when SW_ACK_TURN =>
        rin.count <= (r.count - 1) mod 32;

        if r.count = 0 then
          rin.data_par <= '0';
          rin.sw_state <= SW_DATA;
          -- rin.count <= 31; -- implicit
        end if;

      when SW_DATA =>
        rin.data <= swdio & r.data(31 downto 1);
        rin.count <= (r.count - 1) mod 32;

        if r.count = 0 then
          rin.sw_state <= SW_DATA_PAR;
        end if;

        if r.rnw = '1' then
          rin.data_par <= r.data_par xor r.data(0);
        else
          rin.data_par <= r.data_par xor swdio;
        end if;

      when SW_DATA_PAR =>
        if r.rnw = '1' then
          rin.sw_state <= SW_DATA_TURN;
          rin.count <= r.turnaround;
        elsif r.data_par = swdio then
          rin.sw_state <= SW_IDLE;

          if r.apndp = '0' then
            -- was a write to DP
            case r.a is
              when "00" => -- Abort
                if r.data(0) = '1' then
                  -- AP Abort
                  rin.ap_state <= AP_ABORT;
                end if;

              when "01" => -- Banked
                case r.dp_bank_sel is
                  when "0000" => -- CTRL/Stat
                    rin.ctrl <= r.data;

                  when "0001" => -- DCLR
                    rin.turnaround <= to_integer(unsigned(r.data(9 downto 8)));

                  when others =>
                    null;
                end case;

              when "10" => -- Select
                rin.ap_bank_sel <= r.data(7 downto 4);
                rin.dp_bank_sel <= r.data(3 downto 0);
                rin.ap_sel <= r.data(31 downto 24);

              when "11" => -- RdBuf
                null;

              when others =>
                null;
            end case;
          else
            -- was a write to AP
            rin.ap_state <= AP_WRITE;
            rin.ap_wdata <= r.data;
          end if;
        end if;

      when SW_DATA_TURN =>
        rin.count <= (r.count - 1) mod 32;

        if r.count = 0 then
          rin.sw_state <= SW_IDLE;
        end if;

      when others =>
        null;
    end case;

    case r.ap_state is
      when AP_IDLE | AP_ERROR =>
        null;

      when AP_READ =>
        if dap_i.ready = '1' then
          if dap_i.slverr = '1' then
            rin.ap_state <= AP_ERROR;
          else
            rin.ap_state <= AP_IDLE;
          end if;
          rin.ap_rdbuf <= unsigned(dap_i.rdata);
        end if;

      when AP_WRITE =>
        if dap_i.ready = '1' then
          if dap_i.slverr = '1' then
            rin.ap_state <= AP_ERROR;
          else
            rin.ap_state <= AP_IDLE;
          end if;
        end if;

      when AP_ABORT =>
        if dap_i.ready = '1' then
          rin.ap_state <= AP_IDLE;
        end if;
    end case;
  end process;

  swd_io: process (r) is
  begin
    swd_o.dio.v <= '-';
    swd_o.dio.en <= '0';

    case r.sw_state is
      when SW_ACK_OK =>
        swd_o.dio.v <= boolean_to_logic(r.ack_state = ACK_OK);
        swd_o.dio.en <= '1';

      when SW_ACK_WAIT =>
        swd_o.dio.v <= boolean_to_logic(r.ack_state = ACK_WAIT);
        swd_o.dio.en <= '1';

      when SW_ACK_FAULT =>
        swd_o.dio.v <= boolean_to_logic(r.ack_state = ACK_FAULT);
        swd_o.dio.en <= '1';

      when SW_DATA =>
        swd_o.dio.v <= r.data(0);
        swd_o.dio.en <= r.rnw;

      when SW_DATA_PAR =>
        swd_o.dio.v <= r.data_par;
        swd_o.dio.en <= r.rnw;

      when others =>
        null;
    end case;
  end process;

  dap_io: process (r) is
  begin
    dap_o.enable <= '0';
    dap_o.write <= '0';
    dap_o.addr <= std_ulogic_vector(r.ap_addr);
    dap_o.wdata <= std_ulogic_vector(r.ap_wdata);
    dap_o.abort <= '0';
    dap_o.sel <= '1';

    case r.ap_state is
      when AP_IDLE | AP_ERROR =>
        null;

      when AP_READ =>
        dap_o.enable <= '1';
        dap_o.write <= '0';

      when AP_WRITE =>
        dap_o.enable <= '1';
        dap_o.write <= '1';

      when AP_ABORT =>
        dap_o.enable <= '1';
        dap_o.abort <= '1';
    end case;
  end process;

  ctrl_o <= std_ulogic_vector(r.ctrl);
  
end architecture;
