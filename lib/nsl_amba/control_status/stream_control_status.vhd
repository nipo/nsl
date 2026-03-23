library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_data;
use nsl_amba.control_status.all;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity stream_control_status is
  generic (
    cfg_c          : config_t;
    config_count_c : integer range 1 to 128;
    status_count_c : integer range 1 to 128
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_i   : in nsl_amba.axi4_stream.master_t;
    cmd_o   : out nsl_amba.axi4_stream.slave_t;

    rsp_o   : out nsl_amba.axi4_stream.master_t;
    rsp_i   : in nsl_amba.axi4_stream.slave_t;

    config_o : out control_status_reg_array(0 to config_count_c-1);
    status_i : in  control_status_reg_array(0 to status_count_c-1)  := (others => (others => '-'))
  );
end entity;

architecture rtl of stream_control_status is

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
    last            : boolean;

    data            : std_ulogic_vector(31 downto 0);

    config          : control_status_reg_array(0 to config_count_c-1);
  end record;
  -- TODO use a buffer to send the data in rsp??
  signal status : control_status_reg_array(0 to status_count_c-1);
  
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

  transition: process (r, cmd_i, rsp_i, status)
    variable cno : integer range 0 to 127;
  begin
    rin <= r;
    cno := to_integer(unsigned(r.cmd(6 downto 0)));

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_CMD_GET;

      when STATE_CMD_GET =>
        if is_valid(cfg_c, cmd_i) then
          rin.cmd <= cmd_i.data(0); -- TODO use the nsl_amba.axi4_stream.bytes
                                    -- function! it returns byte_string
          rin.last <= is_last(cfg_c, cmd_i);
          if std_match(cmd_i.data(0), CONTROL_STATUS_REG_WRITE) then
            rin.state <= STATE_CMD_DATA_GET_0;
          else
            rin.state <= STATE_READ;
          end if;
        end if;

      when STATE_CMD_DATA_GET_0 =>
        if is_valid(cfg_c, cmd_i) then
          rin.data(7 downto 0) <= cmd_i.data(0);
          rin.state <= STATE_CMD_DATA_GET_1;
        end if;

      when STATE_CMD_DATA_GET_1 =>
        if is_valid(cfg_c, cmd_i) then
          rin.data(15 downto 8) <= cmd_i.data(0);
          rin.state <= STATE_CMD_DATA_GET_2;
        end if;

      when STATE_CMD_DATA_GET_2 =>
        if is_valid(cfg_c, cmd_i) then
          rin.data(23 downto 16) <= cmd_i.data(0);
          rin.state <= STATE_CMD_DATA_GET_3;
        end if;

      when STATE_CMD_DATA_GET_3 =>
        if is_valid(cfg_c, cmd_i) then
          rin.data(31 downto 24) <= cmd_i.data(0);
          rin.last <= is_last(cfg_c, cmd_i);
          rin.state <= STATE_WRITE;
        end if;

      when STATE_READ =>
        if cno < status_count_c then
          rin.data <= status(cno);
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
        if is_ready(cfg_c, rsp_i) then
          if std_match(r.cmd, CONTROL_STATUS_REG_READ) then
            rin.state <= STATE_RSP_DATA_PUT_0;
          else
            rin.state <= STATE_CMD_GET;
          end if;
        end if;
        
      when STATE_RSP_DATA_PUT_0 =>
        if is_ready(cfg_c, rsp_i) then
          rin.state <= STATE_RSP_DATA_PUT_1;
        end if;

      when STATE_RSP_DATA_PUT_1 =>
        if is_ready(cfg_c, rsp_i) then
          rin.state <= STATE_RSP_DATA_PUT_2;
        end if;

      when STATE_RSP_DATA_PUT_2 =>
        if is_ready(cfg_c, rsp_i) then
          rin.state <= STATE_RSP_DATA_PUT_3;
        end if;

      when STATE_RSP_DATA_PUT_3 =>
        if is_ready(cfg_c, rsp_i) then
          rin.state <= STATE_CMD_GET;
        end if;

    end case;
  end process;

  moore: process (r)
  begin
    cmd_o <= accept(cfg_c, false);
    rsp_o <= transfer_defaults(cfg_c);
    
    case r.state is
      when STATE_RESET | STATE_READ | STATE_WRITE =>
        null;

      when STATE_CMD_GET
        | STATE_CMD_DATA_GET_0 | STATE_CMD_DATA_GET_1 | STATE_CMD_DATA_GET_2 | STATE_CMD_DATA_GET_3 =>
        cmd_o <= accept(cfg_c, true);

      when STATE_RSP_PUT =>
        if std_match(r.cmd, CONTROL_STATUS_REG_READ) then
          rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.cmd), last => false);
        else
          rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.cmd), last => r.last);
        end if;

      when STATE_RSP_DATA_PUT_0 =>
        rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.data(7 downto 0)), last => false);

      when STATE_RSP_DATA_PUT_1 =>
        rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.data(15 downto 8)), last => false);

      when STATE_RSP_DATA_PUT_2 =>
        rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.data(23 downto 16)), last => false);

      when STATE_RSP_DATA_PUT_3 =>
        rsp_o <= transfer(cfg => cfg_c, bytes => from_suv(r.data(31 downto 24)), last => true);

    end case;
  end process;

  status_gen: for i in 0 to status_count_c-1
  generate
    sampler: nsl_clocking.async.async_sampler
      generic map(
        cycle_count_c => 2,
        data_width_c => control_status_reg'length
        )
      port map(
        clock_i => clock_i,
        data_i => status_i(i),
        data_o => status(i)
        );
  end generate;

  config_gen: for i in 0 to config_count_c-1
  generate
    sr: nsl_clocking.interdomain.interdomain_static_reg
      generic map(
        data_width_c => control_status_reg'length
        )
      port map(
        input_clock_i => clock_i,
        data_i => r.config(i),
        data_o => config_o(i)
        );
  end generate;

end architecture;
