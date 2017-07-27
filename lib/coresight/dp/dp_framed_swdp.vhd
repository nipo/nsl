library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;

library coresight;
use coresight.dp.all;

entity dp_framed_swdp is
  port (
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_clk_div  : in  unsigned(15 downto 0);

    p_cmd_val   : in nsl.framed.framed_req;
    p_cmd_ack   : out nsl.framed.framed_ack;

    p_rsp_val   : out nsl.framed.framed_req;
    p_rsp_ack   : in nsl.framed.framed_ack;

    p_swclk    : out std_logic;
    p_swdio_i  : in  std_logic;
    p_swdio_o  : out std_logic;
    p_swdio_oe : out std_logic
  );
end entity;

architecture rtl of dp_framed_swdp is

  signal s_swd_cmd_val  : std_logic;
  signal s_swd_cmd_ack  : std_logic;
  signal s_swd_cmd_data : dp_cmd_data;
  signal s_swd_rsp_val  : std_logic;
  signal s_swd_rsp_ack  : std_logic;
  signal s_swd_rsp_data : dp_rsp_data;

  type state_t is (
    STATE_RESET,

    STATE_CMD_GET,
    STATE_CMD_DATA_GET,

    STATE_SWD_CMD,
    STATE_SWD_RSP,

    STATE_RSP_PUT,
    STATE_RSP_DATA_PUT
    );

  type regs_t is record
    state           : state_t;

    cmd             : std_ulogic_vector(7 downto 0);
    more            : std_ulogic;
    cycle           : natural range 0 to 3;

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

  transition: process (r, p_cmd_val, p_rsp_ack, s_swd_cmd_ack, s_swd_rsp_val, s_swd_rsp_data)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;

      when STATE_CMD_GET =>
        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data;
          rin.more <= p_cmd_val.more;
          if std_match(p_cmd_val.data, DP_CMD_W) or std_match(p_cmd_val.data, DP_CMD_BITBANG) then
            rin.state <= STATE_CMD_DATA_GET;
            rin.cycle <= 3;
          else
            rin.state <= STATE_SWD_CMD;
          end if;
        end if;

      when STATE_CMD_DATA_GET =>
        if p_cmd_val.val = '1' then
          rin.cycle <= (r.cycle - 1) mod 4;
          rin.data <= p_cmd_val.data & r.data(31 downto 8);
          rin.more <= p_cmd_val.more;
          if r.cycle = 0 then
            rin.state <= STATE_SWD_CMD;
          end if;
        end if;

      when STATE_SWD_CMD =>
        if s_swd_cmd_ack = '1' then
          rin.state <= STATE_SWD_RSP;
        end if;

      when STATE_SWD_RSP =>
        if s_swd_rsp_val = '1' then
          if std_match(r.cmd, DP_CMD_RW) then
            rin.data <= s_swd_rsp_data.data;
            rin.cmd(3) <= s_swd_rsp_data.par_ok;
            rin.cmd(2 downto 0) <= s_swd_rsp_data.ack;
          end if;
          rin.state <= STATE_RSP_PUT;
        end if;

      when STATE_RSP_PUT =>
        if p_rsp_ack.ack = '1' then
          if std_match(r.cmd, DP_CMD_R) then
            rin.cycle <= 3;
            rin.state <= STATE_RSP_DATA_PUT;
          else
            rin.state <= STATE_CMD_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.cycle <= (r.cycle - 1) mod 4;
          rin.data <= "--------" & r.data(31 downto 8);
          if r.cycle = 0 then
            rin.state <= STATE_CMD_GET;
          end if;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    s_swd_cmd_val <= '0';
    s_swd_rsp_ack <= '0';
    p_cmd_ack.ack <= '0';
    p_rsp_val.val <= '0';
    p_rsp_val.more <= '-';
    p_rsp_val.data <= (others => '-');

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_CMD_GET
        | STATE_CMD_DATA_GET =>
        p_cmd_ack.ack <= '1';

      when STATE_RSP_PUT =>
        p_rsp_val.val <= '1';
        if std_match(r.cmd, DP_CMD_R) then
          p_rsp_val.more <= '1';
        else
          p_rsp_val.more <= r.more;
        end if;
        p_rsp_val.data <= r.cmd;

      when STATE_RSP_DATA_PUT =>
        p_rsp_val.val <= '1';
        if r.cycle = 0 then
          p_rsp_val.more <= r.more;
        else
          p_rsp_val.more <= '1';
        end if;
        p_rsp_val.data <= r.data(7 downto 0);

      when STATE_SWD_CMD =>
        s_swd_cmd_val <= '1';

      when STATE_SWD_RSP =>
        s_swd_rsp_ack <= '1';
    end case;
  end process;

  swd_port: dp_transactor
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_clk_div => p_clk_div,

      p_cmd_val => s_swd_cmd_val,
      p_cmd_ack => s_swd_cmd_ack,
      p_cmd_data.op => r.cmd,
      p_cmd_data.data => r.data,

      p_rsp_val => s_swd_rsp_val,
      p_rsp_ack => s_swd_rsp_ack,
      p_rsp_data => s_swd_rsp_data,

      p_swclk => p_swclk,
      p_swdio_i => p_swdio_i,
      p_swdio_o => p_swdio_o,
      p_swdio_oe => p_swdio_oe
      );

end architecture;
