library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

entity swdap is
  generic(
    idr: unsigned(31 downto 0) := X"2ba01477"
    );
  port (
    p_swd_c : out nsl_coresight.swd.swd_slave_o;
    p_swd_s : in nsl_coresight.swd.swd_slave_i;
    p_swd_resetn : out std_ulogic;

    p_ap_ready : in std_logic;

    p_ap_sel : out unsigned(7 downto 0);

    p_ap_a : out unsigned(5 downto 0);

    p_ap_rdata : in unsigned(31 downto 0);
    p_ap_rok : in std_logic;
    p_ap_ren : out std_logic;
    
    p_ap_wdata : out unsigned(31 downto 0);
    p_ap_wen : out std_logic
    );
end entity; 

architecture rtl of swdap is

  type state_t is (
    STATE_RESET,
    STATE_IDLE,
    STATE_CMD_AD,
    STATE_CMD_RW,
    STATE_CMD_A0,
    STATE_CMD_A1,
    STATE_CMD_PAR,
    STATE_CMD_STOP,
    STATE_CMD_PARK,
    STATE_CMD_TURN,
    STATE_ACK_OK,
    STATE_ACK_WAIT,
    STATE_ACK_FAULT,
    STATE_ACK_TURN,
    STATE_DATA,
    STATE_DATA_PAR,
    STATE_DATA_TURN
    );

  type regs_t is record
    cmd_a : unsigned(1 downto 0);
    cmd_ad : std_logic;
    cmd_ok : std_logic;
    cmd_rw : std_logic;
    ready : std_logic;
    data : unsigned(31 downto 0);
    data_par : std_logic;
    turnaround : natural range 0 to 3;
    state : state_t;
    to_shift : integer range 0 to 31;
    ap_sel: unsigned(7 downto 0);
    ap_bank_sel: unsigned(3 downto 0);
    dp_bank_sel: unsigned(3 downto 0);
    rdata : unsigned(31 downto 0);
  end record;

  signal r_reset_counter : natural range 0 to 49;

  signal r, rin: regs_t;

  signal s_swdio_out, s_swdio_oe, s_reset: std_logic;
  
  function Boolean_To_Logic(B : Boolean) return std_logic is
  begin
    if B then
      return '1';
    else
      return '0';
    end if;
  end function;
begin
  reg: process (p_swd_s, s_reset) is
  begin
    if p_swd_s.clk = '1' and p_swd_s.clk'event then
      if s_reset = '1' then
        r.state <= STATE_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  reset: process(r, p_swd_s.dio)
  begin
    if to_x01(p_swd_s.dio) = '0' then
      r_reset_counter <= 0;
      s_reset <= '0';
    elsif r_reset_counter /= 49 then
      r_reset_counter <= r_reset_counter + 1;
      s_reset <= '0';
    else
      s_reset <= '1';
    end if;
  end process;

  state: process(r, p_swd_s.dio, p_ap_rdata, p_ap_rok)
  begin
    rin <= r;

    if p_ap_rok = '1' then
      rin.rdata <= p_ap_rdata;
    end if;
    
    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_IDLE;
        rin.turnaround <= 0;
        rin.ap_bank_sel <= (others => '-');
        rin.ap_sel <= (others => '-');
        rin.dp_bank_sel <= (others => '-');
        rin.cmd_a <= (others => '-');
        rin.cmd_ad <= '-';
        rin.cmd_rw <= '-';
        rin.ready <= '0';
        rin.data_par <= '-';
        rin.cmd_ok <= '0';
        rin.rdata <= (others => '-');
        rin.data <= (others => '-');

      when STATE_IDLE =>
        rin.cmd_ok <= '1';
        if to_x01(p_swd_s.dio) = '1' then
          rin.state <= STATE_CMD_AD;
          rin.data_par <= '0';
        end if;

      when STATE_CMD_AD =>
        rin.cmd_ad <= to_x01(p_swd_s.dio);
        rin.state <= STATE_CMD_RW;

      when STATE_CMD_RW =>
        rin.cmd_rw <= to_x01(p_swd_s.dio);
        rin.state <= STATE_CMD_A0;

      when STATE_CMD_A0 =>
        rin.cmd_a(0) <= to_x01(p_swd_s.dio);
        rin.state <= STATE_CMD_A1;

      when STATE_CMD_A1 =>
        rin.cmd_a(1) <= to_x01(p_swd_s.dio);
        rin.state <= STATE_CMD_PAR;

      when STATE_CMD_PAR =>
        rin.state <= STATE_CMD_STOP;
        rin.cmd_ok <= r.cmd_ok and not (to_x01(p_swd_s.dio) xor r.cmd_ad xor r.cmd_rw xor r.cmd_a(0) xor r.cmd_a(1));

      when STATE_CMD_STOP =>
        rin.cmd_ok <= r.cmd_ok and not to_x01(p_swd_s.dio);
        if to_x01(p_swd_s.dio) = '1' then
          rin.state <= STATE_IDLE;
        else
          rin.state <= STATE_CMD_PARK;
        end if;

      when STATE_CMD_PARK =>
        if to_x01(p_swd_s.dio) = '0' then
          rin.state <= STATE_IDLE;
        else
          rin.state <= STATE_CMD_TURN;
          rin.to_shift <= r.turnaround;
        end if;

      when STATE_ACK_OK =>
        rin.state <= STATE_ACK_WAIT;

      when STATE_ACK_WAIT =>
        rin.state <= STATE_ACK_FAULT;

      when STATE_ACK_TURN =>
        rin.to_shift <= (r.to_shift - 1) mod 32;

        if r.to_shift = 0 then
          rin.state <= STATE_DATA;
        end if;
          
      when STATE_CMD_TURN =>
        if r.cmd_ad = '1' or r.cmd_a = "11" then
          rin.ready <= p_ap_ready;
        else
          rin.ready <= '1';
        end if;

        rin.to_shift <= (r.to_shift - 1) mod 32;

        if r.to_shift = 0 then
          if r.cmd_ok = '1' then
            rin.state <= STATE_ACK_OK;
          else
            rin.state <= STATE_IDLE;
          end if;
        end if;
          
      when STATE_ACK_FAULT =>
        rin.to_shift <= 31;

        if r.cmd_rw = '1' then
          if r.cmd_ad = '1' then
            rin.data <= r.rdata;
          else
            rin.data <= (others => '-');

            -- DP read
            case r.cmd_a is
              when "00" => -- IDR
                rin.data <= idr;

              when "01" => -- Banked
                case r.dp_bank_sel is
                  when "0000" => -- CTRL/Stat
                    rin.data <= X"00000000";
                    
                  when "0001" => -- DCLR
                    rin.data(9 downto 8) <= to_unsigned(rin.turnaround, 3);
                    rin.data(7 downto 0) <= X"43";

                  when others =>
                    null;
                end case;
                
              when "10" => -- Select
                null;
                
              when "11" => -- RdBuf
                rin.data <= r.rdata;

              when others =>
                null;
            end case;
          end if;
        end if;

        if r.cmd_ok = '1' and r.ready = '1' then
          if r.cmd_rw = '1' then
            rin.state <= STATE_DATA;
          else
            rin.state <= STATE_ACK_TURN;
            rin.to_shift <= r.turnaround;
          end if;
        else
          rin.state <= STATE_IDLE;
        end if;

      when STATE_DATA =>
        rin.data <= to_x01(p_swd_s.dio) & r.data(31 downto 1);
        rin.to_shift <= (r.to_shift - 1) mod 32;

        if r.to_shift = 0 then
          rin.state <= STATE_DATA_PAR;
        end if;

        if r.cmd_rw = '1' then
          rin.data_par <= r.data_par xor r.data(0);
        else
          rin.data_par <= r.data_par xor to_x01(p_swd_s.dio);
        end if;

      when STATE_DATA_PAR =>
        if r.cmd_rw = '1' then
          rin.state <= STATE_DATA_TURN;
          rin.to_shift <= r.turnaround;
        else
          -- was a write to dp
          if r.cmd_ad = '0' and r.data_par = to_x01(p_swd_s.dio) then
            case r.cmd_a is
              when "00" => -- Abort
                null;

              when "01" => -- Banked
                case r.dp_bank_sel is
                  when "0000" => -- CTRL/Stat
                    null;
                    
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
          end if;
          rin.state <= STATE_IDLE;
        end if;

      when STATE_DATA_TURN =>
        rin.to_shift <= (r.to_shift - 1) mod 32;

        if r.to_shift = 0 then
          rin.state <= STATE_IDLE;
        end if;

      when others =>
        null;
    end case;
  end process;

  p_swd_resetn <= '0' when r.state = STATE_RESET else '1';

  moore_dap: process (r, p_swd_s.dio) is
  begin
    p_ap_wdata <= r.data;
    p_ap_wen <= '0';
    p_ap_ren <= '0';
    p_ap_sel <= r.ap_sel;
    p_ap_a <= r.ap_bank_sel & r.cmd_a;

    case r.state is
      when STATE_DATA_PAR =>
        p_ap_wen <= (not (r.cmd_rw or (r.data_par xor to_x01(p_swd_s.dio)))) and r.cmd_ad;

      when STATE_ACK_FAULT =>
        p_ap_ren <= r.cmd_rw and r.cmd_ad;

      when others =>
        null;
    end case;
  end process;

  swd_io: process (r) is
  begin
    p_swd_c.dio.v <= '-';
    p_swd_c.dio.en <= '0';

    case r.state is
      when STATE_ACK_OK =>
        p_swd_c.dio.v <= r.cmd_ok and r.ready;
        p_swd_c.dio.en <= '1';

      when STATE_ACK_WAIT =>
        p_swd_c.dio.v <= r.cmd_ok and not r.ready;
        p_swd_c.dio.en <= '1';

      when STATE_ACK_FAULT =>
        p_swd_c.dio.v <= not r.cmd_ok;
        p_swd_c.dio.en <= '1';

      when STATE_DATA =>
        p_swd_c.dio.v <= r.data(0);
        p_swd_c.dio.en <= r.cmd_rw;

      when STATE_DATA_PAR =>
        p_swd_c.dio.v <= r.data_par;
        p_swd_c.dio.en <= r.cmd_rw;

      when others =>
        null;
    end case;
  end process;

end architecture;

