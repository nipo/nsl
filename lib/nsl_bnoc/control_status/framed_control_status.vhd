library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;
use nsl_bnoc.control_status.all;

entity framed_control_status is
  generic (
    config_count_c : integer range 1 to 128;
    status_count_c : integer range 1 to 128
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_i   : in nsl_bnoc.framed.framed_req;
    cmd_o   : out nsl_bnoc.framed.framed_ack;

    rsp_o   : out nsl_bnoc.framed.framed_req;
    rsp_i   : in nsl_bnoc.framed.framed_ack;

    config_o : out control_status_reg_array(config_count_c-1 downto 0);
    status_i : in  control_status_reg_array(status_count_c-1 downto 0)  := (others => (others => '-'))
  );
end entity;

architecture rtl of framed_control_status is

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
    last            : std_ulogic;

    data            : std_ulogic_vector(31 downto 0);

    config          : control_status_reg_array(config_count_c-1 downto 0);
  end record;

  signal r, rin : regs_t;

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

  transition: process (r, cmd_i, rsp_i, status_i)
    variable cno : integer range 0 to 127;
  begin
    rin <= r;
    cno := to_integer(unsigned(r.cmd(6 downto 0)));

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;

      when STATE_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.cmd <= cmd_i.data;
          rin.last <= cmd_i.last;
          if std_match(cmd_i.data, CONTROL_STATUS_REG_WRITE) then
            rin.state <= STATE_CMD_DATA_GET_0;
          else
            rin.state <= STATE_READ;
          end if;
        end if;

      when STATE_CMD_DATA_GET_0 =>
        if cmd_i.valid = '1' then
          rin.data(7 downto 0) <= cmd_i.data;
          rin.state <= STATE_CMD_DATA_GET_1;
        end if;

      when STATE_CMD_DATA_GET_1 =>
        if cmd_i.valid = '1' then
          rin.data(15 downto 8) <= cmd_i.data;
          rin.state <= STATE_CMD_DATA_GET_2;
        end if;

      when STATE_CMD_DATA_GET_2 =>
        if cmd_i.valid = '1' then
          rin.data(23 downto 16) <= cmd_i.data;
          rin.state <= STATE_CMD_DATA_GET_3;
        end if;

      when STATE_CMD_DATA_GET_3 =>
        if cmd_i.valid = '1' then
          rin.data(31 downto 24) <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= STATE_WRITE;
        end if;

      when STATE_READ =>
        if cno < status_count_c then
          rin.data <= status_i(cno);
        else
          rin.data <= (others => '-');
        end if;
        rin.state <= STATE_RSP_PUT;
        
      when STATE_WRITE =>
        rin.state <= STATE_RSP_PUT;
        if cno < config_count_c then
          rin.config(cno) <= r.data;
        end if;

      when STATE_RSP_PUT =>
        if rsp_i.ready = '1' then
          if std_match(r.cmd, CONTROL_STATUS_REG_READ) then
            rin.state <= STATE_RSP_DATA_PUT_0;
          else
            rin.state <= STATE_CMD_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT_0 =>
        if rsp_i.ready = '1' then
          rin.state <= STATE_RSP_DATA_PUT_1;
        end if;

      when STATE_RSP_DATA_PUT_1 =>
        if rsp_i.ready = '1' then
          rin.state <= STATE_RSP_DATA_PUT_2;
        end if;

      when STATE_RSP_DATA_PUT_2 =>
        if rsp_i.ready = '1' then
          rin.state <= STATE_RSP_DATA_PUT_3;
        end if;

      when STATE_RSP_DATA_PUT_3 =>
        if rsp_i.ready = '1' then
          rin.state <= STATE_CMD_GET;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    config_o <= r.config;

    case r.state is
      when STATE_RESET | STATE_READ | STATE_WRITE =>
        null;

      when STATE_CMD_GET
        | STATE_CMD_DATA_GET_0 | STATE_CMD_DATA_GET_1 | STATE_CMD_DATA_GET_2 | STATE_CMD_DATA_GET_3 =>
        cmd_o.ready <= '1';

      when STATE_RSP_PUT =>
        rsp_o.valid <= '1';
        if std_match(r.cmd, CONTROL_STATUS_REG_READ) then
          rsp_o.last <= '0';
        else
          rsp_o.last <= r.last;
        end if;
        rsp_o.data <= r.cmd;

      when STATE_RSP_DATA_PUT_0 =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= r.data(7 downto 0);

      when STATE_RSP_DATA_PUT_1 =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= r.data(15 downto 8);

      when STATE_RSP_DATA_PUT_2 =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= r.data(23 downto 16);

      when STATE_RSP_DATA_PUT_3 =>
        rsp_o.valid <= '1';
        rsp_o.last <= r.last;
        rsp_o.data <= r.data(31 downto 24);
    end case;
  end process;

end architecture;
