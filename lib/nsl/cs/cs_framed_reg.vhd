library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.cs.all;

entity cs_framed_reg is
  generic (
    config_count : integer range 1 to 128;
    status_count : integer range 1 to 128
    );
  port (
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
    p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;

    p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
    p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

    p_config_data  : out cs_reg;
    p_config_write : out std_ulogic_vector(config_count-1 downto 0);
    p_status   : in  cs_reg_array(status_count-1 downto 0)
  );
end entity;

architecture rtl of cs_framed_reg is

  signal s_cmd_val   : nsl.fifo.fifo_framed_cmd;
  signal s_cmd_ack   : nsl.fifo.fifo_framed_rsp;
  signal s_rsp_val   : nsl.fifo.fifo_framed_cmd;
  signal s_rsp_ack   : nsl.fifo.fifo_framed_rsp;

  type state_t is (
    STATE_RESET,

    STATE_CMD_GET,
    STATE_CMD_DATA_GET_0,
    STATE_CMD_DATA_GET_1,
    STATE_CMD_DATA_GET_2,
    STATE_CMD_DATA_GET_3,

    STATE_READ,
    STATE_WRITE,

    STATE_RSP_PUT,
    STATE_RSP_DATA_PUT_0,
    STATE_RSP_DATA_PUT_1,
    STATE_RSP_DATA_PUT_2,
    STATE_RSP_DATA_PUT_3
    );

  type regs_t is record
    state           : state_t;

    cmd             : std_ulogic_vector(7 downto 0);
    more            : std_ulogic;

    data            : std_ulogic_vector(31 downto 0);

    config          : cs_reg_array(config_count-1 downto 0);
  end record;

  signal r, rin : regs_t;

begin

  reg: process (p_clk)
    begin
    if rising_edge(p_clk) then
      if p_resetn = '0' then
        r.state <= STATE_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process (r, s_cmd_val, s_rsp_ack, p_status)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;

      when STATE_CMD_GET =>
        if s_cmd_val.val = '1' then
          rin.cmd <= s_cmd_val.data;
          rin.more <= s_cmd_val.more;
          if std_match(s_cmd_val.data, CS_REG_WRITE) then
            rin.state <= STATE_CMD_DATA_GET_0;
          else
            rin.state <= STATE_READ;
          end if;
        end if;

      when STATE_CMD_DATA_GET_0 =>
        if s_cmd_val.val = '1' then
          rin.data(7 downto 0) <= s_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_1;
        end if;

      when STATE_CMD_DATA_GET_1 =>
        if s_cmd_val.val = '1' then
          rin.data(15 downto 8) <= s_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_2;
        end if;

      when STATE_CMD_DATA_GET_2 =>
        if s_cmd_val.val = '1' then
          rin.data(23 downto 16) <= s_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_3;
        end if;

      when STATE_CMD_DATA_GET_3 =>
        if s_cmd_val.val = '1' then
          rin.data(31 downto 24) <= s_cmd_val.data;
          rin.more <= s_cmd_val.more;
          rin.state <= STATE_WRITE;
        end if;

      when STATE_READ =>
        rin.data <= p_status(to_integer(unsigned(r.cmd(6 downto 0))));
        rin.state <= STATE_RSP_PUT;
        
      when STATE_WRITE =>
        rin.state <= STATE_RSP_PUT;

      when STATE_RSP_PUT =>
        if s_rsp_ack.ack = '1' then
          if std_match(r.cmd, CS_REG_READ) then
            rin.state <= STATE_RSP_DATA_PUT_0;
          else
            rin.state <= STATE_CMD_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT_0 =>
        if s_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_1;
        end if;

      when STATE_RSP_DATA_PUT_1 =>
        if s_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_2;
        end if;

      when STATE_RSP_DATA_PUT_2 =>
        if s_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_3;
        end if;

      when STATE_RSP_DATA_PUT_3 =>
        if s_rsp_ack.ack = '1' then
          rin.state <= STATE_CMD_GET;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    s_cmd_ack.ack <= '0';
    s_rsp_val.val <= '0';
    s_rsp_val.more <= '-';
    s_rsp_val.data <= (others => '-');
    p_config_write <= (others => '0');
    p_config_data <= r.data;

    case r.state is
      when STATE_RESET | STATE_READ =>
        null;

      when STATE_WRITE =>
        p_config_write(to_integer(unsigned(r.cmd(6 downto 0)))) <= '1';

      when STATE_CMD_GET
        | STATE_CMD_DATA_GET_0 | STATE_CMD_DATA_GET_1 | STATE_CMD_DATA_GET_2 | STATE_CMD_DATA_GET_3 =>
        s_cmd_ack.ack <= '1';

      when STATE_RSP_PUT =>
        s_rsp_val.val <= '1';
        if std_match(r.cmd, CS_REG_READ) then
          s_rsp_val.more <= '1';
        else
          s_rsp_val.more <= r.more;
        end if;
        s_rsp_val.data <= r.cmd;

      when STATE_RSP_DATA_PUT_0 =>
        s_rsp_val.val <= '1';
        s_rsp_val.more <= '1';
        s_rsp_val.data <= r.data(7 downto 0);

      when STATE_RSP_DATA_PUT_1 =>
        s_rsp_val.val <= '1';
        s_rsp_val.more <= '1';
        s_rsp_val.data <= r.data(15 downto 8);

      when STATE_RSP_DATA_PUT_2 =>
        s_rsp_val.val <= '1';
        s_rsp_val.more <= '1';
        s_rsp_val.data <= r.data(23 downto 16);

      when STATE_RSP_DATA_PUT_3 =>
        s_rsp_val.val <= '1';
        s_rsp_val.more <= r.more;
        s_rsp_val.data <= r.data(31 downto 24);
    end case;
  end process;

  endpoint: nsl.fifo.fifo_framed_endpoint
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_cmd_in_val => p_cmd_val,
      p_cmd_in_ack => p_cmd_ack,
      p_rsp_out_val => p_rsp_val,
      p_rsp_out_ack => p_rsp_ack,

      p_cmd_out_val => s_cmd_val,
      p_cmd_out_ack => s_cmd_ack,
      p_rsp_in_val => s_rsp_val,
      p_rsp_in_ack => s_rsp_ack
      );

end architecture;
