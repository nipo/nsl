library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;

entity jtag_framed_ate is
  port (
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    cmd_i   : in nsl.framed.framed_req;
    cmd_o   : out nsl.framed.framed_ack;
    rsp_o   : out nsl.framed.framed_req;
    rsp_i   : in nsl.framed.framed_ack;

    tck_o  : out std_ulogic;
    tms_o  : out std_ulogic;
    tdi_o  : out std_ulogic;
    tdo_i  : in  std_ulogic
    );
end entity;

architecture rtl of jtag_framed_ate is

  type state_t is (
    ST_RESET,
    ST_CMD_GET,
    ST_CMD_ROUTE,
    ST_SIMPLE_PROCESS,
    ST_DATA_GET,
    ST_DATA_CMD_PUT,
    ST_DATA_RSP_GET,
    ST_DATA_PUT,
    ST_DATA_NEXT,
    ST_RSP_PUT
    );

  constant data_max_size : natural := 8;
  
  type regs_t is
  record
    state : state_t;
    divisor : natural range 0 to 31;
    cmd : std_ulogic_vector(7 downto 0);
    data : std_ulogic_vector(7 downto 0);
    word_left : natural range 0 to 31;
    bit_count_m1 : natural range 0 to data_max_size-1;
    last : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
  signal s_cmd_ready : std_ulogic;
  signal s_cmd_valid : std_ulogic;
  signal s_cmd_op    : nsl.jtag.ate_op;
  signal s_cmd_data  : std_ulogic_vector(data_max_size-1 downto 0);

  signal s_rsp_ready : std_ulogic;
  signal s_rsp_valid : std_ulogic;
  signal s_rsp_data  : std_ulogic_vector(data_max_size-1 downto 0);

begin
  
  reg: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(cmd_i, r, rsp_i,
                      s_cmd_ready, s_rsp_data, s_rsp_valid)
    variable do_write, do_read : boolean;
  begin
    rin <= r;

    do_read := (std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BYTE)
                and std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BYTE_R))
               or (std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BIT)
                   and std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BIT_R));

    do_write := (std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BYTE)
                 and std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BYTE_W))
                or (std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BIT)
                    and std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BIT_W));
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_CMD_GET;

      when ST_CMD_GET =>
        if cmd_i.valid = '1' then
          rin.cmd <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_RSP_PUT;
        end if;

      when ST_RSP_PUT =>
        if rsp_i.ready = '1' then
          rin.state <= ST_CMD_ROUTE;
        end if;

      when ST_CMD_ROUTE =>
        if std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BYTE) then
          rin.word_left <= to_integer(unsigned(r.cmd(4 downto 0)));
          rin.bit_count_m1 <= 7;
          if do_write then
            rin.state <= ST_DATA_GET;
          else
            rin.data <= (others => '0');
            rin.state <= ST_DATA_CMD_PUT;
          end if;
        elsif std_match(r.cmd, nsl.jtag.JTAG_SHIFT_BIT) then
          rin.word_left <= 0;
          rin.bit_count_m1 <= to_integer(unsigned(r.cmd(2 downto 0)));
          if do_write then
            rin.state <= ST_DATA_GET;
          else
            rin.data <= (others => '0');
            rin.state <= ST_DATA_CMD_PUT;
          end if;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_DR_CAPTURE) then
          rin.word_left <= 0;
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_IR_CAPTURE) then
          rin.word_left <= 0;
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_SWD_TO_JTAG) then
          rin.word_left <= 2;
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_RESET_CYCLE) then
          rin.bit_count_m1 <= to_integer(unsigned(r.cmd(2 downto 0)));
          rin.word_left <= 0;
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_RTI_CYCLE) then
          rin.bit_count_m1 <= to_integer(unsigned(r.cmd(2 downto 0)));
          rin.word_left <= 0;
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_RESET) then
          rin.bit_count_m1 <= 7;
          rin.word_left <= to_integer(unsigned(r.cmd(3 downto 0)));
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_RTI) then
          rin.bit_count_m1 <= 7;
          rin.word_left <= to_integer(unsigned(r.cmd(3 downto 0)));
          rin.state <= ST_SIMPLE_PROCESS;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_DIVISOR) then
          rin.divisor <= to_integer(unsigned(r.cmd(4 downto 0)));
          rin.state <= ST_CMD_GET;
        else
          assert false
            report "Unhandled Framed JTAG ATE command"
            severity warning;

          rin.state <= ST_CMD_GET;
        end if;

      when ST_SIMPLE_PROCESS =>
        if s_cmd_ready = '1' then
          if r.word_left /= 0 then
            rin.word_left <= r.word_left - 1;
          else
            rin.state <= ST_CMD_GET;
          end if;
        end if;
        
      when ST_DATA_GET =>
        if cmd_i.valid = '1' then
          rin.data <= cmd_i.data;
          rin.last <= cmd_i.last;
          rin.state <= ST_DATA_CMD_PUT;
        end if;

      when ST_DATA_CMD_PUT =>
        if s_cmd_ready = '1' then
          rin.state <= ST_DATA_RSP_GET;
        end if;

      when ST_DATA_RSP_GET =>
        if s_rsp_valid = '1' then
          rin.data <= s_rsp_data;
          if do_read then
            rin.state <= ST_DATA_PUT;
          else
            rin.state <= ST_DATA_NEXT;
          end if;
        end if;

      when ST_DATA_PUT =>
        if rsp_i.ready = '1' then
            rin.state <= ST_DATA_NEXT;
        end if;

      when ST_DATA_NEXT =>
        if r.word_left = 0 then
          rin.state <= ST_CMD_GET;
        else
          rin.word_left <= r.word_left - 1;
          if do_write then
            rin.state <= ST_DATA_GET;
          else
            rin.data <= (others => '0');
            rin.state <= ST_DATA_CMD_PUT;
          end if;
        end if;
    end case;

  end process;

  moore: process(r)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.last <= '-';
    rsp_o.data <= (others => '-');
    s_cmd_valid <= '0';
    s_cmd_data  <= (others => '-');
    s_rsp_ready <= '0';
    s_cmd_op <= nsl.jtag.ATE_OP_RTI;

    case r.state is
      when ST_RESET | ST_CMD_ROUTE | ST_DATA_NEXT =>
        null;

      when ST_CMD_GET | ST_DATA_GET =>
        cmd_o.ready <= '1';

      when ST_RSP_PUT =>
        rsp_o.data <= r.cmd;
        rsp_o.last <= r.last;
        rsp_o.valid <= '1';

      when ST_SIMPLE_PROCESS =>
        s_cmd_valid <= '1';
        if std_match(r.cmd, nsl.jtag.JTAG_CMD_RESET) or std_match(r.cmd, nsl.jtag.JTAG_CMD_RESET_CYCLE) then
          s_cmd_op <= nsl.jtag.ATE_OP_RESET;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_DR_CAPTURE) then
          s_cmd_op <= nsl.jtag.ATE_OP_DR_CAPTURE;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_IR_CAPTURE) then
          s_cmd_op <= nsl.jtag.ATE_OP_IR_CAPTURE;
        elsif std_match(r.cmd, nsl.jtag.JTAG_CMD_SWD_TO_JTAG) then
          s_cmd_op <= nsl.jtag.ATE_OP_SWD_TO_JTAG_3;
        else
          s_cmd_op <= nsl.jtag.ATE_OP_RTI;
        end if;

      when ST_DATA_CMD_PUT =>
        s_cmd_valid <= '1';
        s_cmd_data <= r.data;
        s_cmd_op <= nsl.jtag.ATE_OP_SHIFT;

      when ST_DATA_RSP_GET =>
        s_rsp_ready <= '1';

      when ST_DATA_PUT =>
        rsp_o.data <= r.data;
        rsp_o.last <= r.last;
        rsp_o.valid <= '1';

    end case;
  end process;

  ate: nsl.jtag.jtag_ate
    generic map (
      data_max_size => data_max_size
      )
    port map (
      reset_n_i => reset_n_i,
      clock_i    => clock_i,
      divisor_i => r.divisor,

      cmd_ready_o => s_cmd_ready,
      cmd_valid_i => s_cmd_valid,
      cmd_op_i => s_cmd_op,
      cmd_data_i => s_cmd_data,
      cmd_size_m1_i => r.bit_count_m1,

      rsp_ready_i => s_rsp_ready,
      rsp_valid_o => s_rsp_valid,
      rsp_data_o => s_rsp_data,

      tck_o => tck_o,
      tms_o => tms_o,
      tdi_o => tdi_o,
      tdo_i => tdo_i
      );

end architecture;
