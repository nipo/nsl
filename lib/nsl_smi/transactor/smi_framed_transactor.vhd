library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_smi;

entity smi_framed_transactor is
  generic(
    clock_freq_c : natural := 150000000;
    mdc_freq_c : natural := 25000000
    );
  port (
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    smi_o   : out nsl_smi.smi.smi_master_o;
    smi_i   : in  nsl_smi.smi.smi_master_i;

    cmd_i   : in nsl_bnoc.framed.framed_req;
    cmd_o   : out nsl_bnoc.framed.framed_ack;
    rsp_o   : out nsl_bnoc.framed.framed_req;
    rsp_i   : in nsl_bnoc.framed.framed_ack
  );
end entity;

architecture rtl of smi_framed_transactor is

  type state_t is (
    ST_RESET,

    ST_CMD_GET,
    ST_CMD_ADDR_GET,
    ST_CMD_DATA_GET_H,
    ST_CMD_DATA_GET_L,

    ST_EXEC_CMD,
    ST_EXEC_RSP,

    ST_RSP_DATA_PUT_H,
    ST_RSP_DATA_PUT_L,
    ST_RSP_STATUS_PUT
    );

  type regs_t is record
    state : state_t;
    cmd   : std_ulogic_vector(7 downto 0);
    addr  : std_ulogic_vector(4 downto 0);
    data  : std_ulogic_vector(15 downto 0);
    error : std_ulogic;
    last  : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal s_smi_cmd_ready, s_smi_rsp_valid, s_smi_rsp_error : std_ulogic;
  signal s_smi_cmd_valid, s_smi_rsp_ready : std_ulogic;
  signal s_smi_rsp_data : std_ulogic_vector(15 downto 0);
  signal s_smi_cmd_op : nsl_smi.master.smi_op_t;

begin

  reg: process (clock_i)
    begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.state <= ST_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process (r, cmd_i, rsp_i,
                       s_smi_cmd_ready,
                       s_smi_rsp_valid, s_smi_rsp_data, s_smi_rsp_error)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CMD_GET;

      when ST_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.cmd <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_CMD_ADDR_GET;
        end if;

      when ST_CMD_ADDR_GET =>
        if cmd_i.valid = '1' then
          rin.addr <= cmd_i.data(rin.addr'range);
          rin.last <= cmd_i.last;

          if std_match(r.cmd, nsl_smi.transactor.SMI_C45_WRITE)
            or std_match(r.cmd, nsl_smi.transactor.SMI_C45_ADDR)
            or std_match(r.cmd, nsl_smi.transactor.SMI_C22_WRITE) then
            rin.state <= ST_CMD_DATA_GET_H;
          else
            rin.state <= ST_EXEC_CMD;
          end if;
        end if;

      when ST_CMD_DATA_GET_H =>
        if cmd_i.valid = '1' then
          rin.data <= cmd_i.data & "--------";
          rin.last <= cmd_i.last;
          rin.state <= ST_CMD_DATA_GET_L;
        end if;

      when ST_CMD_DATA_GET_L =>
        if cmd_i.valid = '1' then
          rin.data(7 downto 0) <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_EXEC_CMD;
        end if;

      when ST_EXEC_CMD =>
        if s_smi_cmd_ready = '1' then
          rin.state <= ST_EXEC_RSP;
        end if;

      when ST_EXEC_RSP =>
        if s_smi_rsp_valid = '1' then
          rin.data <= s_smi_rsp_data;
          rin.error <= s_smi_rsp_error;

          if std_match(r.cmd, nsl_smi.transactor.SMI_C45_WRITE)
            or std_match(r.cmd, nsl_smi.transactor.SMI_C45_ADDR)
            or std_match(r.cmd, nsl_smi.transactor.SMI_C22_WRITE) then
            rin.state <= ST_RSP_STATUS_PUT;
          else
            rin.state <= ST_RSP_DATA_PUT_H;
          end if;
        end if;

      when ST_RSP_DATA_PUT_H =>
        if rsp_i.ready = '1' then
          rin.state <= ST_RSP_DATA_PUT_L;
        end if;

      when ST_RSP_DATA_PUT_L =>
        if rsp_i.ready = '1' then
          rin.state <= ST_RSP_STATUS_PUT;
        end if;
        
      when ST_RSP_STATUS_PUT =>
        if rsp_i.ready = '1' then
          rin.state <= ST_CMD_GET;
        end if;
    end case;
  end process;

  moore: process (r)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');

    s_smi_cmd_valid <= '0';
    s_smi_rsp_ready <= '0';

    if std_match(r.cmd, nsl_smi.transactor.SMI_C45_ADDR) then
      s_smi_cmd_op <= nsl_smi.master.SMI_C45_ADDR;
    elsif std_match(r.cmd, nsl_smi.transactor.SMI_C45_WRITE) then
      s_smi_cmd_op <= nsl_smi.master.SMI_C45_WRITE;
    elsif std_match(r.cmd, nsl_smi.transactor.SMI_C45_READINC) then
      s_smi_cmd_op <= nsl_smi.master.SMI_C45_READINC;
    elsif std_match(r.cmd, nsl_smi.transactor.SMI_C45_READ) then
      s_smi_cmd_op <= nsl_smi.master.SMI_C45_READ;
    elsif std_match(r.cmd, nsl_smi.transactor.SMI_C22_WRITE) then
      s_smi_cmd_op <= nsl_smi.master.SMI_C22_WRITE;
    else
      s_smi_cmd_op <= nsl_smi.master.SMI_C22_READ;
    end if;

    case r.state is
      when ST_RESET =>
      when ST_CMD_GET | ST_CMD_ADDR_GET | ST_CMD_DATA_GET_H | ST_CMD_DATA_GET_L =>
        cmd_o.ready <= '1';

      when ST_EXEC_CMD =>
        s_smi_cmd_valid <= '1';

      when ST_EXEC_RSP =>
        s_smi_rsp_ready <= '1';

      when ST_RSP_DATA_PUT_H =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= r.data(15 downto 8);

      when ST_RSP_DATA_PUT_L =>
        rsp_o.valid <= '1';
        rsp_o.last <= '0';
        rsp_o.data <= r.data(7 downto 0);

      when ST_RSP_STATUS_PUT =>
        rsp_o.valid <= '1';
        rsp_o.last <= r.last;
        rsp_o.data <= (others => '0');
        rsp_o.data(0) <= r.error;
    end case;
  end process;

  master: nsl_smi.master.smi_master
    generic map(
      clock_freq_c => clock_freq_c,
      mdc_freq_c => mdc_freq_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      cmd_valid_i => s_smi_cmd_valid,
      cmd_ready_o => s_smi_cmd_ready,
      cmd_op_i => s_smi_cmd_op,
      cmd_prtad_phyad_i => unsigned(r.cmd(4 downto 0)),
      cmd_devad_regad_i => unsigned(r.addr),
      cmd_data_addr_i => r.data,

      rsp_valid_o => s_smi_rsp_valid,
      rsp_ready_i => s_smi_rsp_ready,
      rsp_data_o => s_smi_rsp_data,
      rsp_error_o => s_smi_rsp_error,

      smi_o => smi_o,
      smi_i => smi_i
      );

end architecture;
