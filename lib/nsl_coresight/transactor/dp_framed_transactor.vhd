library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_coresight, nsl_io, nsl_event;
use nsl_coresight.transactor.all;

entity dp_framed_transactor is
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_i   : in nsl_bnoc.framed.framed_req;
    cmd_o   : out nsl_bnoc.framed.framed_ack;

    rsp_o   : out nsl_bnoc.framed.framed_req;
    rsp_i   : in nsl_bnoc.framed.framed_ack;

    swd_o     : out nsl_coresight.swd.swd_master_o;
    swd_i     : in  nsl_coresight.swd.swd_master_i;

    system_reset_n_o : out nsl_io.io.opendrain
  );
end entity;

architecture rtl of dp_framed_transactor is

  signal s_swd_cmd_valid  : std_logic;
  signal s_swd_cmd_ready  : std_logic;
  signal s_swd_rsp_valid  : std_logic;
  signal s_swd_rsp_ready  : std_logic;
  signal s_swd_rsp_data : dp_rsp_data;

  type state_t is (
    STATE_RESET,

    STATE_CMD_GET,
    STATE_CMD_ROUTE,
    STATE_CMD_DATA_GET,

    STATE_SWD_CMD,
    STATE_SWD_RSP,

    STATE_RSP_PUT,
    STATE_RSP_DATA_PUT
    );

  type regs_t is record
    state           : state_t;

    cmd             : std_ulogic_vector(7 downto 0);
    last            : std_ulogic;
    cycle           : natural range 0 to 3;

    data            : std_ulogic_vector(31 downto 0);

    divisor         : unsigned(15 downto 0);

    srst_drive : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal tick_s : std_ulogic;

begin

  reg: process (clock_i)
    begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.state <= STATE_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process (r, cmd_i, rsp_i, s_swd_cmd_ready, s_swd_rsp_valid, s_swd_rsp_data)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;
        rin.srst_drive <= '0';

      when STATE_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.cmd <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= STATE_CMD_ROUTE;
        end if;

      when STATE_CMD_ROUTE =>
        if std_match(r.cmd, DP_CMD_W) or std_match(r.cmd, DP_CMD_BITBANG) then
          rin.state <= STATE_CMD_DATA_GET;
          rin.cycle <= 3;
        elsif std_match(r.cmd, DP_CMD_DIVISOR) then
          rin.state <= STATE_CMD_DATA_GET;
          rin.cycle <= 1;
          rin.data <= (others => '0');
        elsif std_match(r.cmd, DP_CMD_SYSTEM_RESET) then
          rin.state <= STATE_RSP_PUT;
          rin.srst_drive <= r.cmd(0);
        else
          rin.state <= STATE_SWD_CMD;
        end if;

      when STATE_CMD_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.cycle <= (r.cycle - 1) mod 4;
          rin.data <= cmd_i.data & r.data(31 downto 8);
          rin.last <= cmd_i.last;
          if r.cycle = 0 then
            if std_match(r.cmd, DP_CMD_DIVISOR) then
              rin.divisor <= unsigned(cmd_i.data & r.data(31 downto 24));
              rin.state <= STATE_RSP_PUT;
            else
              rin.state <= STATE_SWD_CMD;
            end if;
          end if;
        end if;

      when STATE_SWD_CMD =>
        if s_swd_cmd_ready = '1' then
          rin.state <= STATE_SWD_RSP;
        end if;

      when STATE_SWD_RSP =>
        if s_swd_rsp_valid = '1' then
          if std_match(r.cmd, DP_CMD_RW) then
            rin.data <= s_swd_rsp_data.data;
            rin.cmd(3) <= s_swd_rsp_data.par_ok;
            rin.cmd(2 downto 0) <= s_swd_rsp_data.ack;
          end if;
          rin.state <= STATE_RSP_PUT;
        end if;

      when STATE_RSP_PUT =>
        if rsp_i.ready = '1' then
          if std_match(r.cmd, DP_CMD_R) then
            rin.cycle <= 3;
            rin.state <= STATE_RSP_DATA_PUT;
          else
            rin.state <= STATE_CMD_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT =>
        if rsp_i.ready = '1' then
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
    s_swd_cmd_valid <= '0';
    s_swd_rsp_ready <= '0';
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    system_reset_n_o.drain_n <= not r.srst_drive;

    case r.state is
      when STATE_RESET | STATE_CMD_ROUTE =>
        null;

      when STATE_CMD_GET
        | STATE_CMD_DATA_GET =>
        cmd_o.ready <= '1';

      when STATE_RSP_PUT =>
        rsp_o.valid <= '1';
        if std_match(r.cmd, DP_CMD_R) then
          rsp_o.last <= '0';
        else
          rsp_o.last <= r.last;
        end if;
        rsp_o.data <= r.cmd;

      when STATE_RSP_DATA_PUT =>
        rsp_o.valid <= '1';
        if r.cycle = 0 then
          rsp_o.last <= r.last;
        else
          rsp_o.last <= '0';
        end if;
        rsp_o.data <= r.data(7 downto 0);

      when STATE_SWD_CMD =>
        s_swd_cmd_valid <= '1';

      when STATE_SWD_RSP =>
        s_swd_rsp_ready <= '1';
    end case;
  end process;

  tick_gen: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      period_m1_i => r.divisor,
      tick_o => tick_s
      );

  swd_port: dp_transactor
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      tick_i => tick_s,
      
      cmd_valid_i => s_swd_cmd_valid,
      cmd_ready_o => s_swd_cmd_ready,
      cmd_data_i.op => r.cmd,
      cmd_data_i.data => r.data,

      rsp_valid_o => s_swd_rsp_valid,
      rsp_ready_i => s_swd_rsp_ready,
      rsp_data_o => s_swd_rsp_data,

      swd_o => swd_o,
      swd_i => swd_i
      );

end architecture;
