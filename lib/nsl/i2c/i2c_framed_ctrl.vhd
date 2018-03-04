library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.i2c.all;

entity i2c_framed_ctrl is
  port(
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_scl       : in  std_ulogic;
    p_scl_drain : out std_ulogic;
    p_sda       : in  std_ulogic;
    p_sda_drain : out std_ulogic;

    p_cmd_val  : in nsl.framed.framed_req;
    p_cmd_ack  : out nsl.framed.framed_ack;
    p_rsp_val  : out nsl.framed.framed_req;
    p_rsp_ack  : in nsl.framed.framed_ack
    );
end entity;

architecture rtl of i2c_framed_ctrl is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_RSP_PUT,
    ST_ACK_PUT,
    ST_DATA_PUT,
    ST_DATA_GET,
    ST_READ,
    ST_WRITE,
    ST_START,
    ST_STOP
    );
  
  type regs_t is record
    state                : state_t;
    more                 : std_ulogic;
    ack                  : std_ulogic;
    data                 : std_ulogic_vector(7 downto 0);
    word_count           : natural range 0 to 63;
    divisor              : std_ulogic_vector(5 downto 0);
  end record;

  signal r, rin : regs_t;

  signal s_wack     :  std_ulogic;
  signal s_rack     :  std_ulogic;
  signal s_rdata    :  std_ulogic_vector(7 downto 0);
  signal s_cmd      :  i2c_cmd_t;
  signal s_busy     :  std_ulogic;
  signal s_done     :  std_ulogic;

begin

  ck : process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition : process (r, p_cmd_val, p_rsp_ack, s_busy, s_done)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.divisor <= (others => '1');
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if p_cmd_val.val = '1' then
          rin.ack <= '-';
          rin.more <= p_cmd_val.more;

          if std_match(p_cmd_val.data, I2C_CMD_READ) then
            rin.state <= ST_READ;
            rin.word_count <= to_integer(unsigned(p_cmd_val.data(5 downto 0)));
            rin.ack <= p_cmd_val.data(6);

          elsif std_match(p_cmd_val.data, I2C_CMD_WRITE) then
            rin.state <= ST_DATA_GET;
            rin.word_count <= to_integer(unsigned(p_cmd_val.data(5 downto 0)));

          elsif std_match(p_cmd_val.data, I2C_CMD_DIV) then
            rin.state <= ST_RSP_PUT;
            rin.divisor <= p_cmd_val.data(rin.divisor'range);

          elsif std_match(p_cmd_val.data, I2C_CMD_START) then
            rin.state <= ST_START;

          elsif std_match(p_cmd_val.data, I2C_CMD_STOP) then
            rin.state <= ST_STOP;
          end if;
        end if;

      when ST_RSP_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_ACK_PUT =>
        if p_rsp_ack.ack = '1' then
          if r.word_count = 0 then
            rin.state <= ST_RSP_PUT;
          else
            rin.state <= ST_DATA_GET;
            rin.word_count <= r.word_count - 1;
          end if;
        end if;

      when ST_DATA_PUT =>
        if p_rsp_ack.ack = '1' then
          if r.word_count = 0 then
            rin.state <= ST_RSP_PUT;
          else
            rin.state <= ST_READ;
            rin.word_count <= r.word_count - 1;
          end if;
        end if;

      when ST_START | ST_STOP =>
        if s_done = '1' then
          rin.state <= ST_RSP_PUT;
        end if;

      when ST_READ =>
        if s_done = '1' then
          rin.state <= ST_DATA_PUT;
          rin.data <= s_rdata;
        end if;

      when ST_WRITE =>
        if s_done = '1' then
          rin.state <= ST_ACK_PUT;
          rin.ack <= s_wack;
        end if;

      when ST_DATA_GET =>
        if p_cmd_val.val = '1' then
          rin.state <= ST_WRITE;
          rin.data <= p_cmd_val.data;
          rin.more <= p_cmd_val.more;
        end if;

    end case;
  end process;

  moore : process (r)
  begin
    case r.state is
      when ST_START =>
        s_cmd <= I2C_START;

      when ST_STOP =>
        s_cmd <= I2C_STOP;

      when ST_READ =>
        s_cmd <= I2C_READ;

      when ST_WRITE =>
        s_cmd <= I2C_WRITE;

      when others =>
        s_cmd <= I2C_NOOP;
    end case;

    case r.state is
      when ST_DATA_PUT =>
        p_rsp_val.val <= '1';
        p_rsp_val.data <= r.data;
        p_rsp_val.more <= '1';

      when ST_RSP_PUT =>
        p_rsp_val.val <= '1';
        p_rsp_val.data <= (others => '0');
        p_rsp_val.more <= r.more;

      when ST_ACK_PUT =>
        p_rsp_val.val <= '1';
        p_rsp_val.data <= "0000000" & r.ack;
        p_rsp_val.more <= '1';

      when others =>
        p_rsp_val.val <= '0';
        p_rsp_val.data <= (others => '-');
        p_rsp_val.more <= '-';
    end case;

    case r.state is
      when ST_DATA_GET | ST_IDLE =>
        p_cmd_ack.ack <= '1';

      when others =>
        p_cmd_ack.ack <= '0';
    end case;
  end process;

  s_rack <= r.ack when r.word_count = 0 else '1';
  
  master: i2c_master
    generic map(
      divisor_width => r.divisor'length
      )
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_divisor => r.divisor,
      p_scl => p_scl,
      p_scl_drain => p_scl_drain,
      p_sda => p_sda,
      p_sda_drain => p_sda_drain,
      p_rack => s_rack,
      p_rdata => s_rdata,
      p_wack => s_wack,
      p_wdata => r.data,
      p_cmd => s_cmd,
      p_busy => s_busy,
      p_done => s_done
      );
  
end architecture;
