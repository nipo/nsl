library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_math, nsl_memory, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;

entity host_controller is
  generic(
    lane_count_c: lane_count_t := 4;
    rx_buffer_byte_count_c: positive := 8
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    sdio_o: out sdio_master_o;
    sdio_i: in sdio_master_i;

    half_cycle_m1_i: in unsigned;
    sample_phase_i: in unsigned;
    width_i: in bus_width_t;
    timeout_cycle_i: in unsigned;
    clock_run_i: in std_ulogic := '1';

    req_i: in txn_req_t;
    req_o: out txn_ack_t;
    stop_i: in std_ulogic := '0';

    rsp_o: out txn_rsp_t;

    tx_valid_i: in std_ulogic := '0';
    tx_data_i: in byte := x"00";
    tx_ready_o: out std_ulogic;

    rx_valid_o: out std_ulogic;
    rx_data_o: out byte;
    rx_ready_i: in std_ulogic := '1'
    );
end entity;

architecture beh of host_controller is

  signal drive_s, sample_s: std_ulogic;
  signal clock_run_s, stall_s, busy_s: std_ulogic;

  signal cmd_req_s: cmd_req_t;
  signal cmd_ack_s: cmd_ack_t;
  signal cmd_rsp_s: cmd_rsp_t;

  signal dat_req_s: dat_req_t;
  signal dat_ack_s: dat_ack_t;
  signal dat_rsp_s: dat_rsp_t;
  signal dat_cancel_s: std_ulogic;

  signal rx_fifo_valid_s: std_ulogic;
  signal rx_fifo_data_s: byte;
  signal rx_room_s: std_ulogic;
  signal rx_free_s: integer range 0 to rx_buffer_byte_count_c;

  type state_t is (
    ST_IDLE,
    -- A read is armed before its command goes out, as a card starts
    -- sending as soon as it has answered.
    ST_ARM_READ,
    ST_CMD,
    ST_CMD_WAIT,
    -- A write is armed once the card has answered, as it only starts
    -- looking for a block then.
    ST_ARM_WRITE,
    ST_DATA,
    ST_CANCEL,
    ST_DONE
    );

  type regs_t is
  record
    state: state_t;

    index: unsigned(5 downto 0);
    argument: unsigned(31 downto 0);
    response: response_kind_t;
    check_crc: boolean;
    data: data_dir_t;
    block_size_m1: unsigned(11 downto 0);
    block_count: unsigned(31 downto 0);

    dat_status: dat_status_t;
    dat_block_count: unsigned(31 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
    end if;
  end process;

  transition: process(r, req_i, cmd_ack_s, cmd_rsp_s, dat_ack_s, dat_rsp_s) is
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        if req_i.valid = '1' then
          rin.index <= req_i.index;
          rin.argument <= req_i.argument;
          rin.response <= req_i.response;
          rin.check_crc <= req_i.check_crc;
          rin.data <= req_i.data;
          rin.block_size_m1 <= req_i.block_size_m1;
          rin.block_count <= req_i.block_count;
          rin.dat_status <= DAT_OK;
          rin.dat_block_count <= (others => '0');

          case req_i.data is
            when DATA_READ =>
              rin.state <= ST_ARM_READ;

            when others =>
              rin.state <= ST_CMD;
          end case;
        end if;

      when ST_ARM_READ =>
        if dat_ack_s.ready = '1' then
          rin.state <= ST_CMD;
        end if;

      when ST_CMD =>
        if cmd_ack_s.ready = '1' then
          rin.state <= ST_CMD_WAIT;
        end if;

      when ST_CMD_WAIT =>
        if cmd_rsp_s.valid = '1' then
          if cmd_rsp_s.status /= CMD_OK then
            -- Nothing is going to come of a data phase whose command
            -- did not get through.
            case r.data is
              when DATA_READ =>
                rin.state <= ST_CANCEL;

              when others =>
                rin.state <= ST_DONE;
            end case;
          else
            case r.data is
              when DATA_NONE =>
                rin.state <= ST_DONE;

              when DATA_READ =>
                rin.state <= ST_DATA;

              when DATA_WRITE =>
                rin.state <= ST_ARM_WRITE;
            end case;
          end if;
        end if;

      when ST_ARM_WRITE =>
        if dat_ack_s.ready = '1' then
          rin.state <= ST_DATA;
        end if;

      when ST_DATA | ST_CANCEL =>
        if dat_rsp_s.valid = '1' then
          rin.state <= ST_DONE;
          rin.dat_status <= dat_rsp_s.status;
          rin.dat_block_count <= dat_rsp_s.block_count;
        end if;

      when ST_DONE =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    req_o <= accept(r.state = ST_IDLE);

    cmd_req_s <= cmd_idle;
    if r.state = ST_CMD then
      cmd_req_s <= cmd_request(to_integer(r.index),
                               r.argument,
                               r.response,
                               r.check_crc);
    end if;

    dat_req_s <= dat_idle;
    case r.state is
      when ST_ARM_READ =>
        dat_req_s.valid <= '1';
        dat_req_s.write <= '0';
        dat_req_s.block_size_m1 <= r.block_size_m1;
        dat_req_s.block_count <= r.block_count;

      when ST_ARM_WRITE =>
        dat_req_s.valid <= '1';
        dat_req_s.write <= '1';
        dat_req_s.block_size_m1 <= r.block_size_m1;
        dat_req_s.block_count <= r.block_count;

      when others =>
        null;
    end case;

    case r.state is
      when ST_CANCEL =>
        dat_cancel_s <= '1';

      when others =>
        dat_cancel_s <= '0';
    end case;

    case r.state is
      when ST_DONE =>
        rsp_o.valid <= '1';

      when others =>
        rsp_o.valid <= '0';
    end case;

    rsp_o.dat_status <= r.dat_status;
    rsp_o.block_count <= r.dat_block_count;
  end process;

  -- A command answers before the blocks it opened have moved, and
  -- whoever is streaming them wants to know then rather than after.
  cmd_answer: process(r, cmd_rsp_s) is
  begin
    case r.state is
      when ST_CMD_WAIT =>
        rsp_o.cmd_valid <= cmd_rsp_s.valid;

      when others =>
        rsp_o.cmd_valid <= '0';
    end case;
  end process;

  -- What the command engine holds of the last answer it got is what
  -- the transaction answers with.
  rsp_o.cmd_status <= cmd_rsp_s.status;
  rsp_o.index <= cmd_rsp_s.index;
  rsp_o.payload <= cmd_rsp_s.payload;

  -- A transaction is clocked whatever a caller asked for: what
  -- clock_run_i says is whether to keep clocking once there is
  -- nothing left to do, which is a choice about a bus that is idle
  -- and not one about a bus that is busy.
  --
  -- A card is only ever made to wait by taking its clock away, which
  -- is what a stall does.
  clock_run_s <= (clock_run_i or busy_s) and not stall_s;

  busy: process(r) is
  begin
    case r.state is
      when ST_IDLE =>
        busy_s <= '0';

      when others =>
        busy_s <= '1';
    end case;
  end process;

  clock_driver: nsl_sdio.link.link_clock_driver
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      half_cycle_m1_i => half_cycle_m1_i,
      sample_phase_i => sample_phase_i,
      run_i => clock_run_s,

      clk_o => sdio_o.clk,
      drive_o => drive_s,
      sample_o => sample_s,
      running_o => open
      );

  cmd_engine: nsl_sdio.link.link_cmd_engine
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      drive_i => drive_s,
      sample_i => sample_s,

      cmd_o => sdio_o.cmd,
      cmd_i => sdio_i.cmd,
      dat0_i => sdio_i.d(0),

      req_i => cmd_req_s,
      req_o => cmd_ack_s,

      rsp_o => cmd_rsp_s,
      busy_o => open
      );

  dat_engine: nsl_sdio.link.link_dat_engine
    generic map(
      lane_count_c => lane_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      drive_i => drive_s,
      sample_i => sample_s,

      d_o => sdio_o.d,
      d_i => sdio_i.d,

      width_i => width_i,

      timeout_cycle_i => timeout_cycle_i,

      req_i => dat_req_s,
      req_o => dat_ack_s,
      stop_i => stop_i,
      cancel_i => dat_cancel_s,

      rsp_o => dat_rsp_s,
      busy_o => open,

      tx_valid_i => tx_valid_i,
      tx_data_i => tx_data_i,
      tx_ready_o => tx_ready_o,

      rx_valid_o => rx_fifo_valid_s,
      rx_data_o => rx_fifo_data_s,
      rx_room_i => rx_room_s,

      stall_o => stall_s
      );

  -- Slack on the read side, and the ready the engine has no room to
  -- offer by itself.  The bus is held while what is left of it would
  -- not cover the period under way.
  rx_room_s <= '1' when rx_free_s >= 2 else '0';

  rx_buffer: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 8,
      word_count_c => rx_buffer_byte_count_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_data_i => rx_fifo_data_s,
      in_valid_i => rx_fifo_valid_s,
      in_free_o => rx_free_s,

      out_data_o => rx_data_o,
      out_valid_o => rx_valid_o,
      out_ready_i => rx_ready_i
      );

end architecture;
