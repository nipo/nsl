library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_sdio;
use nsl_data.crc.all;
use nsl_sdio.link.all;

entity link_cmd_engine is
  generic(
    response_timeout_cycle_c: natural := 64
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    drive_i: in std_ulogic;
    sample_i: in std_ulogic;

    cmd_o: out nsl_io.io.tristated;
    cmd_i: in std_ulogic;
    dat0_i: in std_ulogic;

    req_i: in cmd_req_t;
    req_o: out cmd_ack_t;

    rsp_o: out cmd_rsp_t;
    busy_o: out std_ulogic
    );
end entity;

architecture beh of link_cmd_engine is

  -- Start bit, direction bit, index and argument, which is what a
  -- token's checksum covers
  constant head_bit_count_c: natural := 40;
  -- Bits a checksum takes on the wire
  constant crc_bit_count_c: natural := 7;
  -- Bus periods left between the end of a token and the start of the
  -- next command
  constant gap_cycle_c: natural := 8;
  -- Bus periods a card takes to pull DAT0 low after answering a
  -- command that keeps it busy.  Until they have passed, a released
  -- DAT0 means nothing.
  constant busy_start_cycle_c: natural := 2;

  -- Index of the end bit of an answer, which is also the count of
  -- bits that precede it.
  function last_bit_index(response: response_kind_t) return natural
  is
  begin
    case response is
      when RESP_LONG => return 135;
      when others => return 47;
    end case;
  end function;

  -- Checksum bit a token carries at a given point of the field,
  -- highest coefficient first.
  function crc_bit(state: crc_state_t; index: natural) return std_ulogic
  is
    variable v: std_ulogic_vector(crc_bit_count_c - 1 downto 0);
  begin
    v := crc_spill_vector(cmd_crc_params_c, state);

    return v(crc_bit_count_c - 1 - index);
  end function;

  type state_t is (
    ST_IDLE,
    ST_TX_HEAD,
    ST_TX_CRC,
    ST_TX_END,
    ST_TX_RELEASE,
    ST_RX_WAIT,
    ST_RX,
    ST_BUSY,
    ST_GAP
    );

  type regs_t is
  record
    state: state_t;
    response: response_kind_t;
    check_crc: boolean;

    -- Value held on CMD, and whether it is driven at all.  Both only
    -- ever change on a drive strobe, which is what keeps every bit a
    -- full period wide.
    wire: std_ulogic;
    driving: std_ulogic;

    -- Token going out, highest bit first, checksum excluded: that one
    -- is taken from the state the bits leaving here build up.
    tx: std_ulogic_vector(head_bit_count_c - 1 downto 0);
    -- Token coming in, shifted up as bits arrive, so the first bit
    -- received ends up highest of the bits an answer has
    rx: std_ulogic_vector(135 downto 0);
    bit_index: natural range 0 to 136;
    field_index: natural range 0 to crc_bit_count_c - 1;

    crc: crc_state_t;
    timeout: natural range 0 to response_timeout_cycle_c;
    -- Bus periods to wait through, either before a command or before
    -- believing a released DAT0
    wait_cycle: natural range 0 to gap_cycle_c;

    status: cmd_status_t;
    valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_GAP;
      r.wait_cycle <= gap_cycle_c;
      r.driving <= '0';
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, drive_i, sample_i, cmd_i, dat0_i, req_i) is
  begin
    rin <= r;
    rin.valid <= '0';

    case r.state is
      when ST_IDLE =>
        if req_i.valid = '1' then
          rin.state <= ST_TX_HEAD;
          rin.response <= req_i.response;
          rin.check_crc <= req_i.check_crc;
          rin.tx <= '0' & '1'
                    & std_ulogic_vector(req_i.index)
                    & std_ulogic_vector(req_i.argument);
          rin.crc <= crc_init(cmd_crc_params_c);
          rin.bit_index <= 0;
        end if;

      when ST_TX_HEAD =>
        if drive_i = '1' then
          rin.wire <= r.tx(r.tx'left);
          rin.tx <= r.tx(r.tx'left - 1 downto 0) & '1';
          rin.crc <= crc_update(cmd_crc_params_c, r.crc, r.tx(r.tx'left));
          rin.driving <= '1';

          if r.bit_index = head_bit_count_c - 1 then
            -- What the head leaves in the state is the checksum, so
            -- the field goes out straight from there.
            rin.state <= ST_TX_CRC;
            rin.field_index <= 0;
          else
            rin.bit_index <= r.bit_index + 1;
          end if;
        end if;

      when ST_TX_CRC =>
        if drive_i = '1' then
          rin.wire <= crc_bit(r.crc, r.field_index);

          if r.field_index = crc_bit_count_c - 1 then
            rin.state <= ST_TX_END;
          else
            rin.field_index <= r.field_index + 1;
          end if;
        end if;

      when ST_TX_END =>
        if drive_i = '1' then
          rin.state <= ST_TX_RELEASE;
          rin.wire <= '1';
        end if;

      when ST_TX_RELEASE =>
        if drive_i = '1' then
          -- The end bit has had its period, so the line goes back to
          -- the pull-ups.  It was driven high, so nothing has to
          -- charge it.
          rin.driving <= '0';

          case r.response is
            when RESP_NONE =>
              rin.state <= ST_GAP;
              rin.wait_cycle <= gap_cycle_c;
              rin.status <= CMD_OK;
              rin.valid <= '1';
              -- Nothing came back, so nothing is what the fields of
              -- an answer hold.
              rin.rx <= (others => '0');

            when others =>
              rin.state <= ST_RX_WAIT;
              rin.timeout <= response_timeout_cycle_c;
          end case;
        end if;

      when ST_RX_WAIT =>
        if sample_i = '1' then
          if cmd_i = '0' then
            rin.state <= ST_RX;
            rin.rx <= r.rx(r.rx'left - 1 downto 0) & cmd_i;
            rin.crc <= crc_update(cmd_crc_params_c,
                                  crc_init(cmd_crc_params_c),
                                  cmd_i);
            rin.bit_index <= 1;
          elsif r.timeout = 0 then
            rin.state <= ST_GAP;
            rin.wait_cycle <= gap_cycle_c;
            rin.status <= CMD_TIMEOUT;
            rin.valid <= '1';
            rin.rx <= (others => '0');
          else
            rin.timeout <= r.timeout - 1;
          end if;
        end if;

      when ST_RX =>
        if sample_i = '1' then
          rin.rx <= r.rx(r.rx'left - 1 downto 0) & cmd_i;
          rin.bit_index <= r.bit_index + 1;

          if r.bit_index = 8 and r.response = RESP_LONG then
            -- An answer carrying a register carries the checksum the
            -- card put in it, which covers the register alone.
            rin.crc <= crc_update(cmd_crc_params_c,
                                  crc_init(cmd_crc_params_c),
                                  cmd_i);
          else
            rin.crc <= crc_update(cmd_crc_params_c, r.crc, cmd_i);
          end if;

          if r.bit_index = 1 and cmd_i /= '0' then
            -- Direction bit says this is not a card answering
            rin.state <= ST_GAP;
            rin.wait_cycle <= gap_cycle_c;
            rin.status <= CMD_FRAMING_ERROR;
            rin.valid <= '1';
          elsif r.bit_index = last_bit_index(r.response) then
            if cmd_i /= '1' then
              rin.status <= CMD_FRAMING_ERROR;
            elsif r.check_crc and not crc_is_valid(cmd_crc_params_c, r.crc) then
              rin.status <= CMD_CRC_ERROR;
            else
              rin.status <= CMD_OK;
            end if;

            case r.response is
              when RESP_SHORT_BUSY =>
                rin.state <= ST_BUSY;
                rin.wait_cycle <= busy_start_cycle_c;

              when others =>
                rin.state <= ST_GAP;
                rin.wait_cycle <= gap_cycle_c;
                rin.valid <= '1';
            end case;
          end if;
        end if;

      when ST_BUSY =>
        if sample_i = '1' then
          if r.wait_cycle /= 0 then
            rin.wait_cycle <= r.wait_cycle - 1;
          elsif dat0_i = '1' then
            rin.state <= ST_GAP;
            rin.wait_cycle <= gap_cycle_c;
            rin.valid <= '1';
          end if;
        end if;

      when ST_GAP =>
        if sample_i = '1' then
          if r.wait_cycle = 0 then
            rin.state <= ST_IDLE;
          else
            rin.wait_cycle <= r.wait_cycle - 1;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable payload: std_ulogic_vector(127 downto 0);
  begin
    cmd_o <= nsl_io.io.to_tristated(r.wire, r.driving);
    req_o <= accept(r.state = ST_IDLE);

    case r.state is
      when ST_BUSY =>
        busy_o <= '1';

      when others =>
        busy_o <= '0';
    end case;

    payload := (others => '0');

    case r.response is
      when RESP_LONG =>
        payload := r.rx(127 downto 0);
        rsp_o.index <= unsigned(r.rx(133 downto 128));

      when others =>
        payload(31 downto 0) := r.rx(39 downto 8);
        rsp_o.index <= unsigned(r.rx(45 downto 40));
    end case;

    rsp_o.valid <= r.valid;
    rsp_o.status <= r.status;
    rsp_o.payload <= payload;
  end process;

end architecture;
