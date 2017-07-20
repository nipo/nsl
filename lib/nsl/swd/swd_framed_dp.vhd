library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.swd.all;

entity swd_framed_dp is
  port (
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_clk_div  : in  unsigned(15 downto 0);

    p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
    p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;

    p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
    p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

    p_swclk    : out std_logic;
    p_swdio_i  : in  std_logic;
    p_swdio_o  : out std_logic;
    p_swdio_oe : out std_logic
  );
end entity;

architecture rtl of swd_framed_dp is

  signal s_cmd_val  : std_logic;
  signal s_cmd_ack  : std_logic;
  signal s_cmd_data : swd_cmd_data;
  signal s_rsp_val  : std_logic;
  signal s_rsp_ack  : std_logic;
  signal s_rsp_data : swd_rsp_data;

  type state_t is (
    STATE_RESET,

    STATE_HEADER_GET,
    STATE_HEADER_PUT,

    STATE_TAG_GET,
    STATE_TAG_PUT,

    STATE_CMD_GET,
    STATE_CMD_DATA_GET_0,
    STATE_CMD_DATA_GET_1,
    STATE_CMD_DATA_GET_2,
    STATE_CMD_DATA_GET_3,

    STATE_SWD_CMD,
    STATE_SWD_RSP,

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

  transition: process (r, p_cmd_val, p_rsp_ack, s_cmd_ack, s_rsp_val, s_rsp_data)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_HEADER_GET;

      when STATE_HEADER_GET =>
        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data(3 downto 0) & p_cmd_val.data(7 downto 4);
          rin.state <= STATE_HEADER_PUT;
        end if;

      when STATE_HEADER_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_TAG_GET;
        end if;

      when STATE_TAG_GET =>
        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data;
          rin.state <= STATE_TAG_PUT;
        end if;

      when STATE_TAG_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_CMD_GET;
        end if;

      when STATE_CMD_GET =>
        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data;
          rin.more <= p_cmd_val.more;
          if std_match(p_cmd_val.data, SWD_DP_W) or std_match(p_cmd_val.data, SWD_DP_BITBANG) then
            rin.state <= STATE_CMD_DATA_GET_0;
          else
            rin.state <= STATE_SWD_CMD;
          end if;
        end if;

      when STATE_CMD_DATA_GET_0 =>
        if p_cmd_val.val = '1' then
          rin.data(7 downto 0) <= p_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_1;
        end if;

      when STATE_CMD_DATA_GET_1 =>
        if p_cmd_val.val = '1' then
          rin.data(15 downto 8) <= p_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_2;
        end if;

      when STATE_CMD_DATA_GET_2 =>
        if p_cmd_val.val = '1' then
          rin.data(23 downto 16) <= p_cmd_val.data;
          rin.state <= STATE_CMD_DATA_GET_3;
        end if;

      when STATE_CMD_DATA_GET_3 =>
        if p_cmd_val.val = '1' then
          rin.data(31 downto 24) <= p_cmd_val.data;
          rin.more <= p_cmd_val.more;
          rin.state <= STATE_SWD_CMD;
        end if;

      when STATE_SWD_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_SWD_RSP;
        end if;

      when STATE_SWD_RSP =>
        if s_rsp_val = '1' then
          if std_match(r.cmd, SWD_DP_RW) then
            rin.data <= s_rsp_data.data;
            rin.cmd(3) <= s_rsp_data.par_ok;
            rin.cmd(2 downto 0) <= s_rsp_data.ack;
          end if;
          rin.state <= STATE_RSP_PUT;
        end if;

      when STATE_RSP_PUT =>
        if p_rsp_ack.ack = '1' then
          if std_match(r.cmd, SWD_DP_R) then
            rin.state <= STATE_RSP_DATA_PUT_0;
          elsif r.more = '1' then
            rin.state <= STATE_CMD_GET;
          else
            rin.state <= STATE_HEADER_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT_0 =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_1;
        end if;

      when STATE_RSP_DATA_PUT_1 =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_2;
        end if;

      when STATE_RSP_DATA_PUT_2 =>
        if p_rsp_ack.ack = '1' then
          rin.state <= STATE_RSP_DATA_PUT_3;
        end if;

      when STATE_RSP_DATA_PUT_3 =>
        if p_rsp_ack.ack = '1' then
          if r.more = '1' then
            rin.state <= STATE_CMD_GET;
          else
            rin.state <= STATE_HEADER_GET;
          end if;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    s_cmd_val <= '0';
    s_rsp_ack <= '0';
    p_cmd_ack.ack <= '0';
    p_rsp_val.val <= '0';
    p_rsp_val.more <= '-';
    p_rsp_val.data <= (others => '-');

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_HEADER_GET | STATE_TAG_GET | STATE_CMD_GET
        | STATE_CMD_DATA_GET_0 | STATE_CMD_DATA_GET_1 | STATE_CMD_DATA_GET_2 | STATE_CMD_DATA_GET_3 =>
        p_cmd_ack.ack <= '1';

      when STATE_HEADER_PUT | STATE_TAG_PUT =>
        p_rsp_val.val <= '1';
        p_rsp_val.more <= '1';
        p_rsp_val.data <= r.cmd;

      when STATE_RSP_PUT =>
        p_rsp_val.val <= '1';
        if std_match(r.cmd, SWD_DP_R) then
          p_rsp_val.more <= '1';
        else
          p_rsp_val.more <= r.more;
        end if;
        p_rsp_val.data <= r.cmd;

      when STATE_RSP_DATA_PUT_0 =>
        p_rsp_val.val <= '1';
        p_rsp_val.more <= '1';
        p_rsp_val.data <= r.data(7 downto 0);

      when STATE_RSP_DATA_PUT_1 =>
        p_rsp_val.val <= '1';
        p_rsp_val.more <= '1';
        p_rsp_val.data <= r.data(15 downto 8);

      when STATE_RSP_DATA_PUT_2 =>
        p_rsp_val.val <= '1';
        p_rsp_val.more <= '1';
        p_rsp_val.data <= r.data(23 downto 16);

      when STATE_RSP_DATA_PUT_3 =>
        p_rsp_val.val <= '1';
        p_rsp_val.more <= r.more;
        p_rsp_val.data <= r.data(31 downto 24);

      when STATE_SWD_CMD =>
        s_cmd_val <= '1';

      when STATE_SWD_RSP =>
        s_rsp_ack <= '1';
    end case;
  end process;

  swd_port: swd_dp
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_clk_div => p_clk_div,

      p_cmd_val => s_cmd_val,
      p_cmd_ack => s_cmd_ack,
      p_cmd_data.op => r.cmd,
      p_cmd_data.data => r.data,

      p_rsp_val => s_rsp_val,
      p_rsp_ack => s_rsp_ack,
      p_rsp_data => s_rsp_data,

      p_swclk => p_swclk,
      p_swdio_i => p_swdio_i,
      p_swdio_o => p_swdio_o,
      p_swdio_oe => p_swdio_oe
      );

end architecture;
