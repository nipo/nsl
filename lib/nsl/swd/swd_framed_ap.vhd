library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.swd.all;

entity swd_framed_ap is
  generic(
    source_id : nsl.fifo.component_id
    );
  port (
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
    p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;
    p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
    p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

    p_dp_cmd_val   : in nsl.fifo.fifo_framed_cmd;
    p_dp_cmd_ack   : out nsl.fifo.fifo_framed_rsp;
    p_dp_rsp_val   : out nsl.fifo.fifo_framed_cmd;
    p_dp_rsp_ack   : in nsl.fifo.fifo_framed_rsp
  );
end entity;

architecture rtl of swd_framed_ap is

  type state_t is (
    STATE_RESET,

    STATE_HEADER_GET,
    STATE_HEADER_PUT,

    STATE_TAG_GET,
    STATE_TAG_PUT,

    STATE_DP_HEADER_PUT,
    STATE_DP_TAG_PUT,

    STATE_DP_HEADER_GET,
    STATE_DP_TAG_GET,
    
    STATE_CMD_GET,
    STATE_CMD_ROUTE,

    STATE_DP_SELECT_CMD,
    STATE_DP_SELECT_DATA,
    STATE_DP_SELECT_RSP,

    STATE_DP_RDBUF_CMD,
    STATE_DP_RDBUF_RSP,

    STATE_DP_READ_CMD,
    STATE_DP_READ_RSP,
    STATE_DP_READ_RSP_DATA,

    STATE_DP_WRITE_CMD,
    STATE_DP_WRITE_CMD_DATA,
    STATE_DP_WRITE_RSP,
    );

  type regs_t is record
    state           : state_t;
    dp_id           : nsl.fifo.component_id;

    cmd             : std_ulogic_vector(7 downto 0);
    cmd_pending     : boolean;

    more            : std_ulogic;

    ap_run_pending  : boolean;
    ap_read_pending : boolean;
    data_byte       : natural range 0 to 3;
    ap_run_cycles   : std_ulogic_vector(5 downto 0);
    sel_dirty       : boolean;
    ap_sel          : std_ulogic_vector(7 downto 0);
    ap_bank_sel     : std_ulogic_vector(3 downto 0);
    dp_bank_sel     : std_ulogic_vector(3 downto 0);
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

  transition: process (r, p_cmd_val, p_rsp_ack, p_dp_cmd_val, p_dp_rsp_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_HEADER_GET;
        rin.ap_run_pending <= false;
        rin.ap_read_pending <= false;
        rin.ap_run_cycles <= std_ulogic_vector(to_unsigned(10, 6));
        rin.more <= '0';

      when STATE_HEADER_GET =>
        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data(3 downto 0) & p_cmd_val.data(7 downto 4);
          rin.state <= STATE_HEADER_PUT;
          rin.ap_sel <= x"00";
          rin.ap_bank_sel <= x"0";
          rin.dp_bank_sel <= x"0";
          rin.sel_dirty <= true;
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
        assert not r.cmd_pending report "Command getting overflow" severity failure;

        if p_cmd_val.val = '1' then
          rin.cmd <= p_cmd_val.data;
          rin.more <= p_cmd_val.more;
          rin.state <= STATE_CMD_ROUTE;
          rin.cmd_pending <= true;
        end if;

      when STATE_CMD_ROUTE =>
        if r.ap_run_pending and (not r.cmd_pending or std_match(r.cmd, SWD_AP_AP_RW)) then
          rin.state <= STATE_AP_RUN_CMD;
          rin.ap_run_pending <= false;
        elsif r.ap_read_pending and (not r.cmd_pending or r.more = '0' or not std_match(r.cmd, SWD_AP_AP_READ)) then
          rin.state <= STATE_RDBUF_CMD;
          rin.ap_read_pending <= false;
        elsif not r.cmd_pending then
          if r.more = '1' then
            rin.state <= STATE_CMD_GET;
          else
            rin.state <= STATE_HEADER_GET;
          end if;
        else
          rin.cmd_pending <= false;

          if std_match(r.cmd, SWD_AP_AP_RUN) then
            rin.ap_run_cycles <= r.cmd(5 downto 0);
            rin.state <= STATE_RSP_PUT;

          elsif std_match(r.cmd, SWD_AP_AP_SEL_HIGH) then
            rin.sel_dirty <= r.ap_sel(7 downto 4) /= r.cmd(3 downto 0);
            rin.ap_sel(7 downto 4) <= r.cmd(3 downto 0);
            rin.state <= STATE_RSP_PUT;

          elsif std_match(r.cmd, SWD_AP_AP_SEL_LOW) then
            rin.sel_dirty <= r.ap_sel /= "0000" & r.cmd(3 downto 0);
            rin.ap_sel <= "0000" & r.cmd(3 downto 0);
            rin.state <= STATE_RSP_PUT;

          elsif std_match(r.cmd, SWD_AP_ABORT) then
            rin.state <= STATE_ABORT_CMD;

          elsif std_match(r.cmd, SWD_AP_DP_REG_WRITE) then
            if r.sel_dirty then
              rin.sel_dirty <= false;
              rin.state <= STATE_SELECT_CMD;
              rin.cmd_pending <= true;
            else
              rin.swd_put_rsp <= true;
              rin.swd_data_rsp <= false;
              rin.swd_cmd.op <= SWD_CMD_WRITE;
              rin.swd_cmd.ap <= '0';
              rin.swd_cmd.addr <= unsigned(r.cmd(1 downto 0));
              rin.data_byte <= 3;
              rin.state <= STATE_DATA_PREPARE;
            end if;

          elsif std_match(r.cmd, SWD_AP_DP_REG_READ) then
            if r.sel_dirty then
              rin.sel_dirty <= false;
              rin.state <= STATE_SELECT_CMD;
              rin.cmd_pending <= true;
            else
              rin.swd_put_rsp <= true;
              rin.swd_data_rsp <= true;
              rin.swd_cmd.op <= SWD_CMD_READ;
              rin.swd_cmd.ap <= '0';
              rin.swd_cmd.addr <= unsigned(r.cmd(1 downto 0));
              rin.data_byte <= 3;
              rin.state <= STATE_SWD_CMD;
            end if;

          elsif std_match(r.cmd, SWD_AP_AP_WRITE) then
            if r.sel_dirty or r.ap_bank_sel /= r.cmd(5 downto 2) then
              rin.sel_dirty <= false;
              rin.ap_bank_sel <= r.cmd(5 downto 2);
              rin.state <= STATE_SELECT_CMD;
              rin.cmd_pending <= true;
            else
              rin.swd_put_rsp <= true;
              rin.swd_data_rsp <= false;
              rin.swd_cmd.op <= SWD_CMD_WRITE;
              rin.swd_cmd.ap <= '1';
              rin.swd_cmd.addr <= unsigned(r.cmd(1 downto 0));
              rin.data_byte <= 3;
              rin.state <= STATE_DATA_PREPARE;
            end if;

          elsif std_match(r.cmd, SWD_AP_AP_READ) then
            if r.sel_dirty or r.ap_bank_sel /= r.cmd(5 downto 2) then
              rin.sel_dirty <= false;
              rin.ap_bank_sel <= r.cmd(5 downto 2);
              rin.state <= STATE_SELECT_CMD;
              rin.cmd_pending <= true;
            else
              rin.swd_put_rsp <= r.ap_read_pending;
              rin.swd_data_rsp <= r.ap_read_pending;
              rin.ap_read_pending <= true;
              rin.swd_cmd.op <= SWD_CMD_READ;
              rin.swd_cmd.ap <= '1';
              rin.swd_cmd.addr <= unsigned(r.cmd(1 downto 0));
              rin.data_byte <= 3;
              rin.state <= STATE_SWD_CMD;
            end if;

          elsif std_match(r.cmd, SWD_AP_WAKEUP) then
            rin.state <= STATE_WAKEUP_R1_CMD;
            rin.sel_dirty <= false;
            rin.ap_sel <= X"0";
            rin.ap_bank_sel <= X"0";
            rin.dp_bank_sel <= X"0";
            rin.swd_cmd.op <= SWD_CMD_BITBANG;
            rin.swd_cmd.ap <= '0';
            rin.swd_cmd.addr <= "00";
            rin.swd_cmd.data <= X"ffffffff";

          elsif std_match(r.cmd, SWD_AP_RESET) then
            rin.state <= STATE_RSP_PUT;
            rin.srst <= r.cmd(0);

          elsif std_match(r.cmd, SWD_AP_JTAG_CONFIG) then
            rin.state <= STATE_CLK_DIV;
            rin.data_byte <= 1;

          else
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_CLK_DIV =>
        if p_cmd_val.val = '1' then
          rin.data_byte <= (r.data_byte - 1) mod 4;
          rin.clk_div <= p_cmd_val.data & r.clk_div(15 downto 8);
          rin.more <= p_cmd_val.more;
          if r.data_byte = 0 then
            rin.state <= STATE_RSP_PUT;
          end if;
        end if;

      when STATE_WAKEUP_R1_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_WAKEUP_R1_RSP;
        end if;

      when STATE_WAKEUP_R1_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_WAKEUP_R2_CMD;
          rin.swd_cmd.op <= SWD_CMD_BITBANG;
          rin.swd_cmd.ap <= '0';
          rin.swd_cmd.addr <= "00";
          rin.swd_cmd.data <= X"9effffff";
        end if;

      when STATE_WAKEUP_R2_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_WAKEUP_R2_RSP;
        end if;

      when STATE_WAKEUP_R2_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_WAKEUP_R3_CMD;
          rin.swd_cmd.op <= SWD_CMD_BITBANG;
          rin.swd_cmd.ap <= '0';
          rin.swd_cmd.addr <= "00";
          rin.swd_cmd.data <= X"ffffffe7";
        end if;

      when STATE_WAKEUP_R3_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_WAKEUP_R3_RSP;
        end if;

      when STATE_WAKEUP_R3_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_WAKEUP_R4_CMD;
          rin.swd_cmd.op <= SWD_CMD_BITBANG;
          rin.swd_cmd.ap <= '0';
          rin.swd_cmd.addr <= "00";
          rin.swd_cmd.data <= X"000fffff";
        end if;

      when STATE_WAKEUP_R4_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_WAKEUP_R4_RSP;
        end if;

      when STATE_WAKEUP_R4_RSP =>
        if s_rsp_val = '1' then
          rin.swd_put_rsp <= true;
          rin.swd_data_rsp <= true;
          rin.state <= STATE_SWD_CMD;
          rin.swd_cmd.op <= SWD_CMD_READ;
          rin.swd_cmd.ap <= '0';
          rin.swd_cmd.addr <= "00";
        end if;

      when STATE_DATA_PREPARE =>
        if p_cmd_val.val = '1' then
          rin.data_byte <= (r.data_byte - 1) mod 4;
          rin.swd_cmd.data <= p_cmd_val.data & r.swd_cmd.data(31 downto 8);
          rin.more <= p_cmd_val.more;
          if r.data_byte = 0 then
            rin.state <= STATE_SWD_CMD;
          end if;
        end if;

      when STATE_SWD_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_SWD_RSP;
          rin.ap_run_pending <= r.swd_cmd.ap = '1';
        end if;

      when STATE_SWD_RSP =>
        if s_rsp_val = '1' then
          if r.swd_put_rsp then
            rin.state <= STATE_RSP_PUT;
            rin.swd_cmd.data <= s_rsp_data.data;
            rin.data_byte <= 3;
          else
            rin.state <= STATE_CMD_ROUTE;
          end if;
        end if;

      when STATE_AP_RUN_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_AP_RUN_RSP;
          rin.ap_run_pending <= false;
        end if;

      when STATE_AP_RUN_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_CMD_ROUTE;
        end if;

      when STATE_SELECT_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_SELECT_RSP;
        end if;

      when STATE_RDBUF_CMD =>
        if s_cmd_ack = '1' then
          rin.state <= STATE_RDBUF_RSP;
        end if;

      when STATE_SELECT_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_CMD_ROUTE;
        end if;

      when STATE_RDBUF_RSP =>
        if s_rsp_val = '1' then
          rin.state <= STATE_RSP_PUT;
          rin.swd_cmd.data <= s_rsp_data.data;
          rin.data_byte <= 3;
        end if;

      when STATE_RSP_PUT =>
        if p_rsp_ack.ack = '1' then
          if r.swd_data_rsp then
            rin.state <= STATE_RSP_DATA_PUT;
          else
            rin.state <= STATE_CMD_ROUTE;
          end if;
        end if;

      when STATE_RSP_DATA_PUT =>
        if p_rsp_ack.ack = '1' then
          rin.data_byte <= (r.data_byte - 1) mod 4;
          rin.swd_cmd.data <= "XXXXXXXX" & r.swd_cmd.data(31 downto 8);
          if r.data_byte = 0 then
            rin.state <= STATE_CMD_ROUTE;
          end if;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    case r.state is
      when STATE_WAKEUP_R1_CMD | STATE_WAKEUP_R2_CMD | STATE_WAKEUP_R3_CMD | STATE_WAKEUP_R4_CMD
        | STATE_SWD_CMD =>
        s_cmd_val <= '1';
        s_rsp_ack <= '0';
        s_cmd_data <= r.swd_cmd;

      when STATE_SELECT_CMD =>
        s_cmd_val <= '1';
        s_rsp_ack <= '0';
        s_cmd_data.data <= "0000" & r.ap_sel & "0000000000000000" & r.ap_bank_sel & r.dp_bank_sel;
        s_cmd_data.op <= SWD_CMD_WRITE;
        s_cmd_data.ap <= '0';
        s_cmd_data.addr <= "10";

      when STATE_RDBUF_CMD =>
        s_cmd_val <= '1';
        s_rsp_ack <= '0';
        s_cmd_data.data <= (others => 'X');
        s_cmd_data.op <= SWD_CMD_READ;
        s_cmd_data.ap <= '0';
        s_cmd_data.addr <= "11";

      when STATE_AP_RUN_CMD =>
        s_cmd_val <= '1';
        s_rsp_ack <= '0';
        s_cmd_data.data <=  "0000000000000000000000000" & r.ap_run_cycles & "0";
        s_cmd_data.op <= SWD_CMD_CONST;
        s_cmd_data.ap <= 'X';
        s_cmd_data.addr <= "XX";

      when STATE_WAKEUP_R1_RSP | STATE_WAKEUP_R2_RSP | STATE_WAKEUP_R3_RSP | STATE_WAKEUP_R4_RSP
        | STATE_SWD_RSP | STATE_RDBUF_RSP | STATE_SELECT_RSP | STATE_AP_RUN_RSP =>
        s_cmd_val <= '0';
        s_rsp_ack <= '1';
        s_cmd_data <= r.swd_cmd;
        s_cmd_data.data <= (others => 'X');
        s_cmd_data.op <= "XXX";
        s_cmd_data.ap <= 'X';
        s_cmd_data.addr <= "XX";

      when others =>
        s_cmd_val <= '0';
        s_rsp_ack <= '0';
        s_cmd_data.data <= (others => 'X');
        s_cmd_data.op <= "XXX";
        s_cmd_data.ap <= 'X';
        s_cmd_data.addr <= "XX";
    end case;

    case r.state is
      when STATE_HEADER_GET | STATE_TAG_GET | STATE_CMD_GET | STATE_DATA_PREPARE | STATE_CLK_DIV =>
        p_cmd_ack.ack <= '1';
        p_rsp_val.val <= '0';
        p_rsp_val.more <= 'X';
        p_rsp_val.data <= (others => 'X');

      when STATE_HEADER_PUT | STATE_TAG_PUT =>
        p_cmd_ack.ack <= '0';
        p_rsp_val.val <= '1';
        p_rsp_val.more <= '1';
        p_rsp_val.data <= r.cmd;

      when STATE_RSP_PUT =>
        p_cmd_ack.ack <= '0';
        p_rsp_val.val <= '1';
        if r.swd_data_rsp or r.cmd_pending then
          p_rsp_val.more <= '1';
        else
          p_rsp_val.more <= r.more;
        end if;
        p_rsp_val.data <= r.cmd;

      when STATE_RSP_DATA_PUT =>
        p_cmd_ack.ack <= '0';
        p_rsp_val.val <= '1';
        if r.data_byte /= 0 or r.cmd_pending then
          p_rsp_val.more <= '1';
        else
          p_rsp_val.more <= r.more;
        end if;
        p_rsp_val.data <= r.swd_cmd.data(7 downto 0);

      when others =>
        p_cmd_ack.ack <= '0';
        p_rsp_val.val <= '0';
        p_rsp_val.more <= 'X';
        p_rsp_val.data <= (others => 'X');
    end case;
  end process;

  swd_port: swd_master
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,

      p_clk_div => unsigned(r.clk_div),

      p_cmd_val => s_cmd_val,
      p_cmd_ack => s_cmd_ack,
      p_cmd_data => s_cmd_data,

      p_rsp_val => s_rsp_val,
      p_rsp_ack => s_rsp_ack,
      p_rsp_data => s_rsp_data,

      p_swclk => p_swclk,
      p_swdio_i => p_swdio_i,
      p_swdio_o => p_swdio_o,
      p_swdio_oe => p_swdio_oe
      );

  p_srst <= r.srst;

end architecture;
