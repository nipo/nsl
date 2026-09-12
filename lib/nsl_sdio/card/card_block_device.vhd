library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sdio;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;
use nsl_sdio.card.all;

entity card_block_device is
  generic(
    -- Times to ask a card whether it is done with what it was given
    -- before giving up on it.  A card is allowed a good fraction of a
    -- second to store a block.
    ready_poll_max_c: natural := 100000
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    info_i: in card_info_t;

    req_i: in block_req_t;
    req_o: out block_ack_t;
    stop_i: in std_ulogic := '0';

    rsp_o: out block_rsp_t;

    host_req_o: out txn_req_t;
    host_req_i: in txn_ack_t;
    host_rsp_i: in txn_rsp_t;
    host_stop_o: out std_ulogic
    );
end entity;

architecture beh of card_block_device is

  constant block_byte_count_c: natural := 512;

  type state_t is (
    ST_IDLE,
    ST_RUN_ISSUE,
    ST_RUN_WAIT,
    -- A run of blocks with no count of its own ends with a command,
    -- and so does a counted one: a card keeps going until told to
    -- stop, whatever the host counted.
    ST_STOP_ISSUE,
    ST_STOP_WAIT,
    -- Then it may still be busy with the last block it was given
    ST_POLL_ISSUE,
    ST_POLL_WAIT,
    ST_DONE
    );

  type regs_t is
  record
    state: state_t;
    write: std_ulogic;
    lba: unsigned(31 downto 0);
    count: unsigned(31 downto 0);
    -- Whether the run ends on stop_i rather than on a count
    open_ended: boolean;
    -- Whether the run takes a command to end
    multiple: boolean;
    poll: natural range 0 to ready_poll_max_c;
    status: block_status_t;
    done: unsigned(31 downto 0);
  end record;

  signal r, rin: regs_t;

  -- What a data phase made of itself, as a block user sees it.
  function status_of(cmd: cmd_status_t; dat: dat_status_t)
    return block_status_t
  is
  begin
    if cmd /= CMD_OK then
      return BLOCK_CMD_ERROR;
    end if;

    case dat is
      when DAT_OK =>
        return BLOCK_OK;

      when DAT_WRITE_REJECTED | DAT_WRITE_FAILED =>
        return BLOCK_WRITE_ERROR;

      when DAT_UNDERRUN =>
        return BLOCK_UNDERRUN;

      when others =>
        return BLOCK_DATA_ERROR;
    end case;
  end function;

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

  transition: process(r, req_i, host_req_i, host_rsp_i) is
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        if req_i.valid = '1' then
          rin.state <= ST_RUN_ISSUE;
          rin.write <= req_i.write;
          rin.lba <= req_i.lba;
          rin.count <= req_i.count;
          rin.open_ended <= req_i.count = 0;
          rin.multiple <= req_i.count /= 1;
          rin.status <= BLOCK_OK;
          rin.done <= (others => '0');
          rin.poll <= 0;
        end if;

      when ST_RUN_ISSUE =>
        if host_req_i.ready = '1' then
          rin.state <= ST_RUN_WAIT;
        end if;

      when ST_RUN_WAIT =>
        if host_rsp_i.valid = '1' then
          rin.status <= status_of(host_rsp_i.cmd_status,
                                  host_rsp_i.dat_status);
          rin.done <= host_rsp_i.block_count;

          if host_rsp_i.cmd_status /= CMD_OK then
            -- Nothing was started, so there is nothing to stop.
            rin.state <= ST_DONE;
          elsif r.multiple then
            rin.state <= ST_STOP_ISSUE;
          else
            rin.state <= ST_DONE;
          end if;
        end if;

      when ST_STOP_ISSUE =>
        if host_req_i.ready = '1' then
          rin.state <= ST_STOP_WAIT;
        end if;

      when ST_STOP_WAIT =>
        if host_rsp_i.valid = '1' then
          if host_rsp_i.cmd_status /= CMD_OK then
            rin.status <= BLOCK_CMD_ERROR;
            rin.state <= ST_DONE;
          else
            rin.state <= ST_POLL_ISSUE;
          end if;
        end if;

      when ST_POLL_ISSUE =>
        if host_req_i.ready = '1' then
          rin.state <= ST_POLL_WAIT;
        end if;

      when ST_POLL_WAIT =>
        if host_rsp_i.valid = '1' then
          if host_rsp_i.cmd_status /= CMD_OK then
            rin.status <= BLOCK_CMD_ERROR;
            rin.state <= ST_DONE;
          elsif (host_rsp_i.payload(31 downto 0)
                 and status_error_mask_c) /= x"00000000"
          then
            -- The card had something to say about the run, which only
            -- its status carries.
            rin.status <= BLOCK_CMD_ERROR;
            rin.state <= ST_DONE;
          elsif host_rsp_i.payload(12 downto 9) = status_state_transfer_c then
            rin.state <= ST_DONE;
          elsif r.poll = ready_poll_max_c then
            rin.status <= BLOCK_WRITE_ERROR;
            rin.state <= ST_DONE;
          else
            rin.poll <= r.poll + 1;
            rin.state <= ST_POLL_ISSUE;
          end if;
        end if;

      when ST_DONE =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    req_o <= accept(r.state = ST_IDLE);

    case r.state is
      when ST_DONE =>
        rsp_o.valid <= '1';

      when others =>
        rsp_o.valid <= '0';
    end case;

    rsp_o.status <= r.status;
    rsp_o.count <= r.done;
  end process;

  -- What goes to the host depends on what the card turned out to be,
  -- which is not this block's state.
  mealy: process(r, info_i) is
  begin
    host_req_o <= txn_idle;

    case r.state is
      when ST_RUN_ISSUE =>
        -- A card that addresses blocks takes the number of one, and
        -- one that does not takes the offset of its first byte.
        if r.write = '1' then
          if r.multiple then
            host_req_o <= txn_write(25, unsigned'(x"00000000"),
                                    block_byte_count_c, 0);
          else
            host_req_o <= txn_write(24, unsigned'(x"00000000"),
                                    block_byte_count_c, 1);
          end if;
        else
          if r.multiple then
            host_req_o <= txn_read(18, unsigned'(x"00000000"),
                                   block_byte_count_c, 0);
          else
            host_req_o <= txn_read(17, unsigned'(x"00000000"),
                                   block_byte_count_c, 1);
          end if;
        end if;

        if info_i.block_addressed then
          host_req_o.argument <= r.lba;
        else
          host_req_o.argument <= shift_left(r.lba, 9);
        end if;

        if not r.open_ended then
          host_req_o.block_count <= r.count;
        end if;

      when ST_STOP_ISSUE =>
        -- A read has data on DAT0 where a card signals it is busy, so
        -- only a write waits for that here.
        if r.write = '1' then
          host_req_o <= txn_command(12, unsigned'(x"00000000"),
                                    RESP_SHORT_BUSY);
        else
          host_req_o <= txn_command(12, unsigned'(x"00000000"),
                                    RESP_SHORT);
        end if;

      when ST_POLL_ISSUE =>
        host_req_o <= txn_command(13, info_i.rca & x"0000", RESP_SHORT);

      when others =>
        null;
    end case;
  end process;

  host_stop_o <= stop_i;

end architecture;
