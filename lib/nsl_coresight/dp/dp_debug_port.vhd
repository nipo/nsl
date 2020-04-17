library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

entity dp_debug_port is
  generic(
    idr: unsigned(31 downto 0) := X"2ba01477"
    );
  port (
    p_swd_c : out nsl_coresight.swd.swd_slave_c;
    p_swd_s : in nsl_coresight.swd.swd_slave_s;

    p_swd_clk    : out std_ulogic;
    p_swd_resetn : out std_ulogic;

    p_ap_cmd : out nsl_coresight.dp.ap_cmd;
    p_ap_rsp : in  nsl_coresight.dp.ap_rsp
    );
end entity;

architecture rtl of dp_debug_port is

  type state_t is (
    STATE_IDLE,
    STATE_CMD_SHIFT,
    STATE_CMD_TURN,
    STATE_ACK_SHIFT,
    STATE_ACK_TURN,
    STATE_DATA_SHIFT_IN,
    STATE_DATA_SHIFT_OUT,
    STATE_DATA_PAR_IN,
    STATE_DATA_PAR_OUT,
    STATE_DATA_TURN,
    STATE_ERR_FLUSH
    );

  type regs_t is record
    reset_counter : natural range 0 to 49;
    bit_counter   : natural range 0 to 40;
    cmd_apndp     : std_ulogic;
    cmd_rnw       : std_ulogic;
    cmd_a         : std_ulogic_vector(1 downto 0);
    cmd_valid     : boolean;

    shreg         : std_ulogic_vector(31 downto 0);
    parity_in     : std_ulogic;
    parity_out    : std_ulogic;

    turnaround    : natural range 0 to 3;
    state         : state_t;

    ap_error      : std_ulogic;
    ap_sel        : natural range 0 to 255;
    ap_bank_sel   : std_ulogic_vector(3 downto 0);
    dp_bank_sel   : std_ulogic_vector(3 downto 0);
    rdbuff        : std_ulogic_vector(31 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin
  
  reg: process (p_swd_s.clk) is
  begin
    if rising_edge(p_swd_s.clk) then
      r <= rin;
    end if;
  end process;

  state: process(r, p_swd_s.dio.v, p_ap_rdata, p_ap_rok)
    variable shreg_en : boolean;
  begin
    rin <= r;
    shreg_en := false;
    
    if p_swd_s.dio.v = '0' then
      rin.reset_counter <= 49;
    elsif r.reset_counter /= 0 then
      rin.reset_counter <= r.reset_counter - 1;
    end if;

    if r.reset_counter = 0 then
      rin.state       <= STATE_RESET;
      rin.turnaround  <= 0;
      rin.ap_bank_sel <= (others => '0');
      rin.ap_sel      <= 0;
      rin.dp_bank_sel <= (others => '0');
    else
      case r.state is
        when STATE_IDLE =>
          rin.parity_in <= '0';
          rin.bit_counter <= 6;

          if p_swd_s.dio.v = '1' then
            rin.state <= STATE_CMD_SHIFT;
          end if;

        when STATE_CMD_SHIFT =>
          shreg_en := true;

          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            -- shreg: stop, par, a3, a2, rnw, apndp
            rin.cmd_apndp <= r.shreg(r.shreg'left - 5);
            rin.cmd_rnw <= r.shreg(r.shreg'left - 4);
            rin.cmd_a <= r.shreg(r.shreg'left - 2 downto r.shreg'left - 3);
            rin.cmd_valid <= r.shreg(r.shreg'left) = '0'
                             and p_swd_s.dio.v = '1'
                             and r.parity_in = '0';

            rin.state <= STATE_CMD_TURN;
          end if;

        when STATE_CMD_TURN =>
          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          elsif not r.cmd_valid then
            rin.state <= STATE_ERR_FLUSH;
            rin.bit_counter <= 32 + 1 + 3 + 3;
          else
            if r.cmd_apndp = '0' or r.ap_ready then
              rin.shreg <= (0 => '1', 1 => '0', 2 => '0', others => '-');
            else
              rin.shreg <= (0 => '0', 1 => '1', 2 => '0', others => '-');
            end if;
            rin.state <= STATE_ACK_SHIFT;
            rin.bit_counter <= 2;
          end if;

        when STATE_ACK_SHIFT =>
          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
            shreg_en := true;
          elsif r.cmd_rnw = '0' then
            rin.state <= STATE_ACK_TURN;
            rin.bit_counter <= r.turnaround;

            rin.parity_out <= '-';
            rin.parity_in <= '-';
            rin.shreg <= (others => '-');
          else
            rin.parity_out <= '0';
            rin.parity_in <= '-';
            rin.state <= STATE_DATA_SHIFT_OUT;
            rin.bit_counter <= 31;

            rin.shreg <= (others => '-');

            if r.cmd_apndp = '1' or r.cmd_a = "11" then
              rin.shreg <= r.rdbuff;
            elsif r.cmd_a = "00" then -- IDR
              rin.shreg <= idr;
            elsif r.cmd_a = "01" then -- banked
              rin.shreg <= X"00000000";
              case r.dp_bank_sel & r.cmd_a is
                when 0 => -- CTRL/Stat
                  null;

                when 1 => -- DCLR
                  rin.shreg(9 downto 8) <= to_unsigned(r.turnaround, 3);
                  rin.shreg(7 downto 0) <= X"43";

                when others =>
                  null;
              end case;
              
            else -- 10 / Resend
              null;
            end if;
          end if;

        when STATE_ACK_TURN =>
          rin.bit_counter <= 31;
          rin.parity_in <= '0';
          rin.parity_out <= '-';

          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            rin.state <= STATE_DATA_SHIFT_IN;
          end if;

        when STATE_DATA_SHIFT_IN =>
          shreg_en := true;

          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            rin.state <= STATE_DATA_PAR_IN;
          end if;

        when STATE_DATA_SHIFT_OUT =>
          shreg_en := true;

          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            rin.state <= STATE_DATA_PAR_OUT;
          end if;

        when STATE_DATA_PAR_OUT =>
          rin.state <= STATE_DATA_TURN;
          rin.bit_counter <= r.turnaround;

        when STATE_DATA_PAR_IN =>
          rin.state <= STATE_IDLE;
          if p_swd_s.dio.v /= r.parity_in then
            rin.data_error <= true;
          else
            if r.cmd_apndp = '0' then
              case r.cmd_a is
                when "00" => -- Abort
                  r.ap_error <= '0';
                when "01" => -- Banked
                  case r.dp_bank_sel is
                    when 1 => -- DCLR
                      rin.turnaround <= to_integer(unsigned(r.shreg(8 downto 8)));
                    when others =>
                      null;
                  end case;
                when "10" => -- select
                  rin.ap_bank_sel <= r.shreg(7 downto 4);
                  rin.dp_bank_sel <= to_integer(unsigned(r.shreg(3 downto 0)));
                  rin.ap_sel <= to_integer(unsigned(r.shreg(31 downto 24)));
                when "11" => -- ?
              end case;
            else
              rin.ap_busy <= true;
              rin.ap_wdata <= r.shreg;
              rin.ap_write <= '1';
              rin.ap_read <= '0';
              rin.ap_a <= r.ap_bank_sel & r.cmd_a;
            end if;
          end if;

        when STATE_DATA_TURN =>
          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            rin.state <= STATE_IDLE;
          end if;

        when STATE_ERR_FLUSH =>
          if r.bit_counter /= 0 then
            rin.bit_counter <= r.bit_counter - 1;
          else
            rin.state <= STATE_IDLE;
          end if;

      end case;
    end if;

    if shreg_en then
      rin.parity_in <= r.parity_in xor p_swd_s.dio.v;
      rin.shreg <= p_swd_s.dio.v & r.shreg(r.shreg'left downto 1);
    end if;
    
  end process;

  p_swd_clk <= p_swd_s.clk;
  p_swd_resetn <= '0' when r.reset_counter = 0 else '1';

  swdio_o: process (r) is
  begin
    case r.state is
      when STATE_ACK_SHIFT =>
        p_swd_c.dio.en <= '1';
        p_swd_c.dio.v <= r.ack(0);

      when STATE_DATA_SHIFT_OUT =>
        p_swd_c.dio.en <= '1';
        p_swd_c.dio.v <= r.data(0);

      when STATE_DATA_PAR_OUT =>
        p_swd_c.dio.en <= '1';
        p_swd_c.dio.v <= r.data_par;

      when others =>
        p_swd_c.dio.v <= '-';
        p_swd_c.dio.en <= '0';
    end case;
  end process;

end architecture;
