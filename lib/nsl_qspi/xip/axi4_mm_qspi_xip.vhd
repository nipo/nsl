library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_qspi;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_qspi.transactor.all;

entity axi4_mm_qspi_xip is
  generic(
    config_c: nsl_amba.axi4_mm.config_t
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    config_i: in nsl_qspi.xip.xip_config_t;

    axi_i: in nsl_amba.axi4_mm.master_t;
    axi_o: out nsl_amba.axi4_mm.slave_t;

    cmd_o: out nsl_bnoc.framed.framed_req;
    cmd_i: in nsl_bnoc.framed.framed_ack;
    rsp_i: in nsl_bnoc.framed.framed_req;
    rsp_o: out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of axi4_mm_qspi_xip is

  constant bus_byte_count_c: positive := 2**config_c.data_bus_width_l2;
  constant command_max_c: positive := 17;

  subtype bus_data_t is byte_string(0 to bus_byte_count_c-1);
  subtype command_t is byte_string(0 to command_max_c-1);

  type rd_state_t is (
    RD_RESET,
    RD_IDLE,
    RD_PREPARE,
    RD_SEND_COMMAND,
    RD_RECEIVE,
    RD_DATA,
    RD_ERROR
    );
  type wr_state_t is (
    WR_RESET,
    WR_DRAIN,
    WR_RESPONSE
    );

  type regs_t is
  record
    rd_state: rd_state_t;
    transaction: nsl_amba.axi4_mm.transaction_t;
    config: nsl_qspi.xip.xip_config_t;
    command: command_t;
    command_length: natural range 0 to command_max_c;
    command_position: natural range 0 to command_max_c-1;
    response_position: natural range 0 to bus_byte_count_c+1;
    response_error: boolean;
    read_data: bus_data_t;
    wr_state: wr_state_t;
    write_address_seen: boolean;
    write_data_done: boolean;
    write_id: nsl_amba.axi4_mm.id_t;
  end record;

  signal r, rin: regs_t;

  function selected_profile(cfg: nsl_qspi.xip.xip_config_t)
    return nsl_qspi.xip.read_profile_t is
  begin
    if cfg.quad_enable then
      return cfg.quad_profile;
    end if;

    return cfg.single_profile;
  end function;

  function beat_byte_count(txn: nsl_amba.axi4_mm.transaction_t)
    return positive is
  begin
    return 2**to_integer(size_l2(config_c, txn));
  end function;

  function lane_number(txn: nsl_amba.axi4_mm.transaction_t) return natural is
  begin
    if config_c.data_bus_width_l2 = 0 then
      return 0;
    end if;

    return to_integer(address(config_c, txn)(config_c.data_bus_width_l2-1 downto 0));
  end function;

  function flash_address(txn: nsl_amba.axi4_mm.transaction_t;
                         cfg: nsl_qspi.xip.xip_config_t)
    return unsigned is
    variable ret: unsigned(64 downto 0);
  begin
    ret := resize(address(config_c, txn), ret'length)
      + resize(cfg.flash_offset, ret'length);
    return ret;
  end function;

  function request_valid(a: nsl_amba.axi4_mm.address_t;
                         cfg: nsl_qspi.xip.xip_config_t) return boolean is
    variable start_v: unsigned(64 downto 0);
    variable final_v: unsigned(64 downto 0);
    variable flash_v: unsigned(64 downto 0);
    variable increment_v: natural range 0 to 32767;
    variable beat_bytes_v: positive range 1 to 128;
    variable beat_count_v: positive range 1 to 256;
    variable profile_v: nsl_qspi.xip.read_profile_t;
  begin
    start_v := resize(address(config_c, a), start_v'length);
    beat_bytes_v := 2**to_integer(size_l2(config_c, a));
    beat_count_v := to_integer(length_m1(config_c, a, 8)) + 1;
    if burst(config_c, a) = BURST_INCR then
      increment_v := beat_bytes_v * beat_count_v - 1;
    else
      increment_v := beat_bytes_v - 1;
    end if;
    final_v := start_v + increment_v;
    flash_v := final_v + resize(cfg.flash_offset, flash_v'length);
    profile_v := selected_profile(cfg);

    if not cfg.enabled
      or lock(config_c, a) /= LOCK_NORMAL
      or (burst(config_c, a) /= BURST_INCR and burst(config_c, a) /= BURST_FIXED)
      or to_integer(size_l2(config_c, a)) > config_c.data_bus_width_l2 then
      return false;
    end if;
    for i in 0 to config_c.data_bus_width_l2-1 loop
      if i < to_integer(size_l2(config_c, a)) and start_v(i) /= '0' then
        return false;
      end if;
    end loop;
    if final_v(64 downto config_c.address_width) /= 0
      or start_v(64 downto 12) /= final_v(64 downto 12)
      or flash_v(64 downto 32) /= 0 then
      return false;
    end if;
    if not profile_v.address_32 and flash_v(31 downto 24) /= x"00" then
      return false;
    end if;
    return true;
  end function;

  function make_command(txn: nsl_amba.axi4_mm.transaction_t;
                        cfg: nsl_qspi.xip.xip_config_t) return command_t is
    variable ret: command_t := (others => x"00");
    variable pos: natural range 0 to command_max_c;
    variable address_v: unsigned(64 downto 0);
    variable profile_v: nsl_qspi.xip.read_profile_t;
    variable address_bytes_v: positive range 3 to 4;
  begin
    profile_v := selected_profile(cfg);
    address_v := flash_address(txn, cfg);
    if profile_v.address_32 then
      address_bytes_v := 4;
    else
      address_bytes_v := 3;
    end if;

    ret(0) := qspi_cmd_timing_c;
    ret(1) := std_ulogic_vector(to_unsigned(cfg.divider-1, 8));
    ret(2) := x"00";
    ret(3) := x"00";
    ret(4) := qspi_cmd_tx1_c;
    ret(5) := x"00";
    ret(6) := profile_v.opcode;
    if profile_v.address_quad then
      ret(7) := qspi_cmd_tx4_c;
    else
      ret(7) := qspi_cmd_tx1_c;
    end if;
    ret(8) := std_ulogic_vector(to_unsigned(address_bytes_v-1, 8));
    pos := 9;
    if address_bytes_v = 4 then
      ret(pos) := std_ulogic_vector(address_v(31 downto 24));
      pos := pos + 1;
    end if;
    ret(pos) := std_ulogic_vector(address_v(23 downto 16));
    ret(pos+1) := std_ulogic_vector(address_v(15 downto 8));
    ret(pos+2) := std_ulogic_vector(address_v(7 downto 0));
    pos := pos + 3;
    if profile_v.dummy_cycles /= 0 then
      ret(pos) := qspi_cmd_dummy_c;
      ret(pos+1) := std_ulogic_vector(to_unsigned(profile_v.dummy_cycles-1, 8));
      pos := pos + 2;
    end if;
    if cfg.quad_enable then
      ret(pos) := qspi_cmd_rx4_c;
    else
      ret(pos) := qspi_cmd_rx1_c;
    end if;
    ret(pos+1) := std_ulogic_vector(to_unsigned(beat_byte_count(txn)-1, 8));
    return ret;
  end function;

  function command_length(cfg: nsl_qspi.xip.xip_config_t) return positive is
    variable ret: positive range 14 to command_max_c;
    variable profile_v: nsl_qspi.xip.read_profile_t;
  begin
    ret := 14;
    profile_v := selected_profile(cfg);
    if profile_v.address_32 then
      ret := ret + 1;
    end if;
    if profile_v.dummy_cycles /= 0 then
      ret := ret + 2;
    end if;
    return ret;
  end function;

begin

  assert config_c.data_bus_width_l2 <= 7
    report "QSPI XIP supports AXI data buses up to 1024 bits"
    severity failure;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.rd_state <= RD_RESET;
      r.wr_state <= WR_RESET;
      r.write_address_seen <= false;
      r.write_data_done <= false;
    end if;
  end process;

  transition: process(r, config_i, axi_i, cmd_i, rsp_i)
  begin
    rin <= r;

    case r.rd_state is
      when RD_RESET =>
        rin.rd_state <= RD_IDLE;

      when RD_IDLE =>
        if is_valid(config_c, axi_i.ar) then
          rin.transaction <= transaction(config_c, axi_i.ar);
          rin.config <= config_i;
          if request_valid(axi_i.ar, config_i) then
            rin.rd_state <= RD_PREPARE;
          else
            rin.rd_state <= RD_ERROR;
          end if;
        end if;

      when RD_PREPARE =>
        rin.command <= make_command(r.transaction, r.config);
        rin.command_length <= command_length(r.config);
        rin.command_position <= 0;
        rin.response_position <= 0;
        rin.response_error <= false;
        rin.read_data <= (others => x"00");
        rin.rd_state <= RD_SEND_COMMAND;

      when RD_SEND_COMMAND =>
        if cmd_i.ready = '1' then
          if r.command_position = r.command_length-1 then
            rin.rd_state <= RD_RECEIVE;
          else
            rin.command_position <= r.command_position + 1;
          end if;
        end if;

      when RD_RECEIVE =>
        if rsp_i.valid = '1' then
          if rsp_i.last = '1' then
            if r.response_position /= beat_byte_count(r.transaction)
              or rsp_i.data /= qspi_status_ok_c then
              rin.response_error <= true;
            end if;
            rin.rd_state <= RD_DATA;
          elsif r.response_position < beat_byte_count(r.transaction) then
            rin.read_data(lane_number(r.transaction) + r.response_position) <= rsp_i.data;
            rin.response_position <= r.response_position + 1;
          else
            rin.response_error <= true;
            if r.response_position < bus_byte_count_c+1 then
              rin.response_position <= r.response_position + 1;
            end if;
          end if;
        end if;

      when RD_DATA =>
        if is_ready(config_c, axi_i.r) then
          if is_last(config_c, r.transaction) then
            rin.rd_state <= RD_IDLE;
          else
            rin.transaction <= step(config_c, r.transaction);
            rin.rd_state <= RD_PREPARE;
          end if;
        end if;

      when RD_ERROR =>
        if is_ready(config_c, axi_i.r) then
          if is_last(config_c, r.transaction) then
            rin.rd_state <= RD_IDLE;
          else
            rin.transaction <= step(config_c, r.transaction);
          end if;
        end if;
    end case;

    case r.wr_state is
      when WR_RESET =>
        rin.wr_state <= WR_DRAIN;
        rin.write_address_seen <= false;
        rin.write_data_done <= false;

      when WR_DRAIN =>
        if not r.write_address_seen and is_valid(config_c, axi_i.aw) then
          rin.write_address_seen <= true;
          rin.write_id <= axi_i.aw.id;
        end if;

        if not r.write_data_done and is_valid(config_c, axi_i.w)
          and is_last(config_c, axi_i.w) then
          rin.write_data_done <= true;
        end if;

        if (r.write_address_seen or is_valid(config_c, axi_i.aw))
          and (r.write_data_done
               or (is_valid(config_c, axi_i.w) and is_last(config_c, axi_i.w))) then
          rin.wr_state <= WR_RESPONSE;
        end if;

      when WR_RESPONSE =>
        if is_ready(config_c, axi_i.b) then
          rin.wr_state <= WR_DRAIN;
          rin.write_address_seen <= false;
          rin.write_data_done <= false;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    axi_o.aw <= handshake_defaults(config_c);
    axi_o.w <= handshake_defaults(config_c);
    axi_o.b <= write_response_defaults(config_c);
    axi_o.ar <= handshake_defaults(config_c);
    axi_o.r <= read_data_defaults(config_c);
    cmd_o <= nsl_bnoc.framed.framed_req_idle_c;
    rsp_o <= nsl_bnoc.framed.framed_ack_idle_c;

    if r.rd_state = RD_IDLE then
      axi_o.ar <= accept(config_c, true);
    elsif r.rd_state = RD_SEND_COMMAND then
      cmd_o <= nsl_bnoc.framed.framed_flit(
        r.command(r.command_position),
        last => r.command_position = r.command_length-1);
    elsif r.rd_state = RD_RECEIVE then
      rsp_o <= nsl_bnoc.framed.framed_accept(true);
    elsif r.rd_state = RD_DATA then
      if r.response_error then
        axi_o.r <= read_data(config_c,
                             id => id(config_c, r.transaction),
                             bytes => r.read_data,
                             resp => RESP_SLVERR,
                             user => user(config_c, r.transaction),
                             last => is_last(config_c, r.transaction),
                             valid => true);
      else
        axi_o.r <= read_data(config_c,
                             id => id(config_c, r.transaction),
                             bytes => r.read_data,
                             resp => RESP_OKAY,
                             user => user(config_c, r.transaction),
                             last => is_last(config_c, r.transaction),
                             valid => true);
      end if;
    elsif r.rd_state = RD_ERROR then
      axi_o.r <= read_data(config_c,
                           id => id(config_c, r.transaction),
                           bytes => null_byte_string,
                           resp => RESP_SLVERR,
                           user => user(config_c, r.transaction),
                           last => is_last(config_c, r.transaction),
                           valid => true);
    end if;

    if r.wr_state = WR_DRAIN then
      axi_o.aw <= accept(config_c, not r.write_address_seen);
      axi_o.w <= accept(config_c, not r.write_data_done);
    elsif r.wr_state = WR_RESPONSE then
      axi_o.b <= write_response(config_c,
                                id => r.write_id(config_c.id_width-1 downto 0),
                                resp => RESP_SLVERR,
                                valid => true);
    end if;
  end process;
end architecture;
