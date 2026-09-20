library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_qspi, nsl_bnoc, nsl_data, nsl_io;
use nsl_qspi.transactor.all;
use nsl_data.bytestream.all;

entity qspi_framed_transactor is
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    qspi_o: out nsl_qspi.qspi.qspi_master_o;
    qspi_i: in nsl_qspi.qspi.qspi_master_i;
    cmd_i: in nsl_bnoc.framed.framed_req;
    cmd_o: out nsl_bnoc.framed.framed_ack;
    rsp_o: out nsl_bnoc.framed.framed_req;
    rsp_i: in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of qspi_framed_transactor is

  type state_t is (
    ST_COLLECT,
    ST_HEADER,
    ST_CHECK_OP,
    ST_CHECK_COUNT,
    ST_CHECK_PAYLOAD,
    ST_SETUP,
    ST_EXEC_OP,
    ST_EXEC_COUNT,
    ST_LOAD_BYTE,
    ST_LOW_HALF,
    ST_HIGH_HALF,
    ST_STORE_BYTE,
    ST_HOLD_CS,
    ST_HIGH_CS,
    ST_RESPONSE
    );

  type regs_t is
  record
    state: state_t;
    command: byte_string(0 to qspi_command_max_c-1);
    response: byte_string(0 to qspi_response_max_c-1);
    length: natural range 0 to qspi_command_max_c;
    cursor: natural range 0 to qspi_command_max_c;
    read_count: natural range 0 to qspi_response_max_c;
    response_pos: natural range 0 to qspi_response_max_c;
    remaining: natural range 0 to 256;
    op: byte;
    shift: byte;
    symbol: natural range 0 to 7;
    timer: natural range 0 to 255;
    divider: natural range 0 to 255;
    setup_time: natural range 0 to 255;
    high_time: natural range 0 to 255;
    error: boolean;
  end record;

  signal r, rin: regs_t;

  function decoded_count(v: byte) return positive is
  begin
    return to_integer(unsigned(v)) + 1;
  end function;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_COLLECT;
      r.length <= 0;
      r.cursor <= 0;
      r.read_count <= 0;
      r.response_pos <= 0;
      r.remaining <= 0;
      r.op <= x"00";
      r.shift <= x"00";
      r.symbol <= 0;
      r.timer <= 0;
      r.divider <= 0;
      r.setup_time <= 0;
      r.high_time <= 0;
      r.error <= false;
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, qspi_i)
  begin
    rin <= r;

    case r.state is
      when ST_COLLECT =>
        if cmd_i.valid = '1' then
          if r.length < qspi_command_max_c then
            rin.command(r.length) <= cmd_i.data;
            rin.length <= r.length + 1;
          else
            rin.error <= true;
          end if;
          if cmd_i.last = '1' then
            rin.state <= ST_HEADER;
          end if;
        end if;

      when ST_HEADER =>
        if r.error or r.length < 4 or r.command(0) /= qspi_cmd_timing_c then
          rin.error <= true;
          rin.state <= ST_RESPONSE;
        else
          rin.divider <= to_integer(unsigned(r.command(1)));
          rin.setup_time <= to_integer(unsigned(r.command(2)));
          rin.high_time <= to_integer(unsigned(r.command(3)));
          rin.cursor <= 4;
          rin.state <= ST_CHECK_OP;
        end if;

      when ST_CHECK_OP =>
        if r.cursor = r.length then
          rin.cursor <= 4;
          rin.read_count <= 0;
          rin.timer <= r.setup_time;
          rin.state <= ST_SETUP;
        elsif r.command(r.cursor) = qspi_cmd_tx1_c
          or r.command(r.cursor) = qspi_cmd_tx4_c
          or r.command(r.cursor) = qspi_cmd_rx1_c
          or r.command(r.cursor) = qspi_cmd_rx4_c
          or r.command(r.cursor) = qspi_cmd_dummy_c then
          rin.op <= r.command(r.cursor);
          rin.cursor <= r.cursor + 1;
          rin.state <= ST_CHECK_COUNT;
        else
          rin.error <= true;
          rin.read_count <= 0;
          rin.state <= ST_RESPONSE;
        end if;

      when ST_CHECK_COUNT =>
        if r.cursor = r.length then
          rin.error <= true;
          rin.read_count <= 0;
          rin.state <= ST_RESPONSE;
        else
          rin.cursor <= r.cursor + 1;
          rin.remaining <= decoded_count(r.command(r.cursor));
          if r.op = qspi_cmd_tx1_c or r.op = qspi_cmd_tx4_c then
            rin.state <= ST_CHECK_PAYLOAD;
          elsif r.op = qspi_cmd_rx1_c or r.op = qspi_cmd_rx4_c then
            if r.read_count + decoded_count(r.command(r.cursor)) > qspi_response_max_c then
              rin.error <= true;
              rin.read_count <= 0;
              rin.state <= ST_RESPONSE;
            else
              rin.read_count <= r.read_count + decoded_count(r.command(r.cursor));
              rin.state <= ST_CHECK_OP;
            end if;
          else
            rin.state <= ST_CHECK_OP;
          end if;
        end if;

      when ST_CHECK_PAYLOAD =>
        if r.cursor = r.length then
          rin.error <= true;
          rin.read_count <= 0;
          rin.state <= ST_RESPONSE;
        else
          rin.cursor <= r.cursor + 1;
          rin.remaining <= r.remaining - 1;
          if r.remaining = 1 then
            rin.state <= ST_CHECK_OP;
          end if;
        end if;

      when ST_SETUP =>
        if r.timer = 0 then
          rin.state <= ST_EXEC_OP;
        else
          rin.timer <= r.timer - 1;
        end if;

      when ST_EXEC_OP =>
        if r.cursor = r.length then
          rin.timer <= r.divider;
          rin.state <= ST_HOLD_CS;
        else
          rin.op <= r.command(r.cursor);
          rin.cursor <= r.cursor + 1;
          rin.state <= ST_EXEC_COUNT;
        end if;

      when ST_EXEC_COUNT =>
        rin.remaining <= decoded_count(r.command(r.cursor));
        rin.cursor <= r.cursor + 1;
        rin.state <= ST_LOAD_BYTE;

      when ST_LOAD_BYTE =>
        rin.shift <= x"00";
        rin.symbol <= 0;
        rin.timer <= r.divider;
        rin.state <= ST_LOW_HALF;
        if r.op = qspi_cmd_tx1_c or r.op = qspi_cmd_tx4_c then
          rin.shift <= r.command(r.cursor);
          rin.cursor <= r.cursor + 1;
        end if;

      when ST_LOW_HALF =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= r.divider;
          rin.state <= ST_HIGH_HALF;
          if r.op = qspi_cmd_rx1_c then
            rin.shift <= r.shift(6 downto 0) & qspi_i.dq(1);
          elsif r.op = qspi_cmd_rx4_c then
            rin.shift <= r.shift(3 downto 0) & qspi_i.dq;
          end if;
        end if;

      when ST_HIGH_HALF =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= r.divider;
          if r.op = qspi_cmd_dummy_c
            or ((r.op = qspi_cmd_tx4_c or r.op = qspi_cmd_rx4_c) and r.symbol = 1)
            or r.symbol = 7 then
            rin.state <= ST_STORE_BYTE;
          else
            rin.symbol <= r.symbol + 1;
            rin.state <= ST_LOW_HALF;
            if r.op = qspi_cmd_tx1_c then
              rin.shift <= r.shift(6 downto 0) & '0';
            elsif r.op = qspi_cmd_tx4_c then
              rin.shift <= r.shift(3 downto 0) & "0000";
            end if;
          end if;
        end if;

      when ST_STORE_BYTE =>
        if r.op = qspi_cmd_rx1_c or r.op = qspi_cmd_rx4_c then
          rin.response(r.read_count) <= r.shift;
          rin.read_count <= r.read_count + 1;
        end if;
        rin.remaining <= r.remaining - 1;
        if r.remaining = 1 then
          rin.state <= ST_EXEC_OP;
        else
          rin.state <= ST_LOAD_BYTE;
        end if;

      when ST_HOLD_CS =>
        if r.timer = 0 then
          rin.timer <= r.high_time;
          rin.state <= ST_HIGH_CS;
        else
          rin.timer <= r.timer - 1;
        end if;

      when ST_HIGH_CS =>
        if r.timer = 0 then
          rin.state <= ST_RESPONSE;
        else
          rin.timer <= r.timer - 1;
        end if;

      when ST_RESPONSE =>
        if rsp_i.ready = '1' then
          if r.response_pos = r.read_count then
            rin.state <= ST_COLLECT;
            rin.length <= 0;
            rin.cursor <= 0;
            rin.read_count <= 0;
            rin.response_pos <= 0;
            rin.error <= false;
          else
            rin.response_pos <= r.response_pos + 1;
          end if;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    cmd_o <= nsl_bnoc.framed.framed_accept(r.state = ST_COLLECT);
    rsp_o <= nsl_bnoc.framed.framed_req_idle_c;
    qspi_o <= nsl_qspi.qspi.qspi_master_idle_c;

    if r.state = ST_HIGH_HALF then
      qspi_o.sck <= '1';
    end if;

    case r.state is
      when ST_SETUP | ST_EXEC_OP | ST_EXEC_COUNT
        | ST_LOAD_BYTE | ST_HOLD_CS =>
        qspi_o.cs_n <= '0';

      when ST_LOW_HALF | ST_HIGH_HALF | ST_STORE_BYTE =>
        qspi_o.cs_n <= '0';

        if r.op = qspi_cmd_tx1_c or r.op = qspi_cmd_rx1_c then
          qspi_o.dq(2) <= nsl_io.io.to_tristated('1');
          qspi_o.dq(3) <= nsl_io.io.to_tristated('1');
        end if;

        if r.op = qspi_cmd_tx1_c then
          qspi_o.dq(0) <= nsl_io.io.to_tristated(r.shift(7));
        elsif r.op = qspi_cmd_tx4_c then
          for i in 0 to 3 loop
            qspi_o.dq(i) <= nsl_io.io.to_tristated(r.shift(i+4));
          end loop;
        end if;

      when ST_RESPONSE =>
        if r.response_pos /= r.read_count then
          rsp_o <= nsl_bnoc.framed.framed_flit(r.response(r.response_pos));
        elsif r.error then
          rsp_o <= nsl_bnoc.framed.framed_flit(qspi_status_error_c, last => true);
        else
          rsp_o <= nsl_bnoc.framed.framed_flit(qspi_status_ok_c, last => true);
        end if;
      when others => null;
    end case;
  end process;
end architecture;
