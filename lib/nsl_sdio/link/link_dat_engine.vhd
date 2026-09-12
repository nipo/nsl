library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;

entity link_dat_engine is
  generic(
    lane_count_c: lane_count_t := 4
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    drive_i: in std_ulogic;
    sample_i: in std_ulogic;

    d_o: out nsl_io.io.tristated_vector(max_lane_count_c - 1 downto 0);
    d_i: in std_ulogic_vector(max_lane_count_c - 1 downto 0);

    width_i: in bus_width_t;

    timeout_cycle_i: in unsigned;

    req_i: in dat_req_t;
    req_o: out dat_ack_t;
    stop_i: in std_ulogic := '0';
    cancel_i: in std_ulogic := '0';

    rsp_o: out dat_rsp_t;
    busy_o: out std_ulogic;

    tx_valid_i: in std_ulogic;
    tx_data_i: in byte;
    tx_ready_o: out std_ulogic;

    rx_valid_o: out std_ulogic;
    rx_data_o: out byte;
    rx_room_i: in std_ulogic := '1';

    stall_o: out std_ulogic
    );
end entity;

architecture beh of link_dat_engine is

  -- Bits a checksum takes on the wires, per line
  constant crc_bit_count_c: natural := 16;
  -- Bus periods a card takes to say what it made of a block, counted
  -- from the end of that block
  constant status_start_cycle_c: natural := 2;

  type crc_state_vector is array (natural range <>) of crc_state_t;

  -- Bit of a byte one line reaches.  Only the lines in use are ever
  -- looked at, and this keeps the others inside the byte rather than
  -- past its end, which is what an index has to be whether or not
  -- anything reads it.
  function bit_index(base: natural; lane: natural) return natural
  is
  begin
    return (base + lane) mod 8;
  end function;

  -- Bits of a byte the lines carry together, highest on the highest
  -- line in use.  A line carries them from the top of the byte down,
  -- so base walks down to zero.
  function group_of(data: byte;
                    base: natural;
                    lane_count: lane_count_t)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(lane_count_c - 1 downto 0)
      := (others => '1');
  begin
    for k in 0 to lane_count_c - 1
    loop
      if k < lane_count then
        ret(k) := data(bit_index(base, k));
      end if;
    end loop;

    return ret;
  end function;

  function group_merged(data: byte;
                        d: std_ulogic_vector;
                        base: natural;
                        lane_count: lane_count_t)
    return byte
  is
    variable ret: byte := data;
  begin
    for k in 0 to lane_count_c - 1
    loop
      if k < lane_count then
        ret(bit_index(base, k)) := d(k);
      end if;
    end loop;

    return ret;
  end function;

  -- Every line keeps its own checksum, over the bits that line
  -- carried and no others.
  function crc_updated(state: crc_state_vector;
                       d: std_ulogic_vector;
                       lane_count: lane_count_t)
    return crc_state_vector
  is
    variable ret: crc_state_vector(0 to lane_count_c - 1) := state;
  begin
    for k in 0 to lane_count_c - 1
    loop
      if k < lane_count then
        ret(k) := crc_update(dat_crc_params_c, state(k), d(k));
      end if;
    end loop;

    return ret;
  end function;

  function crc_all_valid(state: crc_state_vector;
                         lane_count: lane_count_t) return boolean
  is
    variable ret: boolean := true;
  begin
    for k in 0 to lane_count_c - 1
    loop
      if k < lane_count
        and not crc_is_valid(dat_crc_params_c, state(k))
      then
        ret := false;
      end if;
    end loop;

    return ret;
  end function;

  -- Checksum bit a line puts on the wires at a given point of the
  -- field, highest coefficient first.
  function crc_bit(state: crc_state_t; index: natural) return std_ulogic
  is
    variable v: std_ulogic_vector(crc_bit_count_c - 1 downto 0);
  begin
    v := crc_spill_vector(dat_crc_params_c, state);

    return v(crc_bit_count_c - 1 - index);
  end function;

  function crc_group(state: crc_state_vector;
                     index: natural;
                     lane_count: lane_count_t)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(lane_count_c - 1 downto 0)
      := (others => '1');
  begin
    for k in 0 to lane_count_c - 1
    loop
      if k < lane_count then
        ret(k) := crc_bit(state(k), index);
      end if;
    end loop;

    return ret;
  end function;

  type state_t is (
    ST_IDLE,

    ST_RX_WAIT,
    ST_RX_DATA,
    ST_RX_CRC,
    ST_RX_END,

    ST_TX_FETCH,
    ST_TX_START,
    ST_TX_DATA,
    ST_TX_CRC,
    ST_TX_END,
    ST_TX_RELEASE,
    ST_TX_STATUS_WAIT,
    ST_TX_STATUS,
    ST_TX_BUSY,

    ST_BLOCK_END,
    ST_DONE
    );

  type regs_t is
  record
    state: state_t;
    write: std_ulogic;
    lane_count: lane_count_t;
    block_size_m1: unsigned(11 downto 0);
    block_left: unsigned(31 downto 0);
    open_ended: boolean;
    block_done: unsigned(31 downto 0);

    -- Byte on its way through, and the bit of it the lowest line in
    -- use carries this period
    data: byte;
    base: natural range 0 to 7;
    byte_left: unsigned(11 downto 0);

    crc: crc_state_vector(0 to lane_count_c - 1);
    field_index: natural range 0 to crc_bit_count_c - 1;

    wire: std_ulogic_vector(lane_count_c - 1 downto 0);
    driving: std_ulogic;

    timeout: unsigned(timeout_cycle_i'length - 1 downto 0);
    wait_cycle: natural range 0 to status_start_cycle_c;

    status: dat_status_t;
    rx_valid: std_ulogic;
    rx_data: byte;
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
      r.driving <= '0';
      r.rx_valid <= '0';
    end if;
  end process;

  transition: process(r, drive_i, sample_i, d_i, width_i, timeout_cycle_i,
                      req_i, stop_i, cancel_i, tx_valid_i, tx_data_i) is
    variable merged: byte;
  begin
    rin <= r;
    rin.rx_valid <= '0';

    merged := group_merged(r.data, d_i, r.base, r.lane_count);

    case r.state is
      when ST_IDLE =>
        if req_i.valid = '1' then
          assert lane_count(width_i) <= lane_count_c
            report "Bus was switched to more data lines than this host "
            & "is wired for"
            severity failure;

          rin.write <= req_i.write;
          rin.lane_count <= lane_count(width_i);
          -- Kept in step with the line count from here on, so that
          -- the bits a group covers always sit inside a byte.
          rin.base <= 8 - lane_count(width_i);
          rin.block_size_m1 <= req_i.block_size_m1;
          rin.block_left <= req_i.block_count;
          rin.open_ended <= req_i.block_count = 0;
          rin.block_done <= (others => '0');
          rin.status <= DAT_OK;
          rin.timeout <= timeout_cycle_i;

          if req_i.write = '1' then
            rin.state <= ST_TX_FETCH;
          else
            rin.state <= ST_RX_WAIT;
          end if;
        end if;

      when ST_RX_WAIT =>
        if sample_i = '1' then
          if d_i(0) = '0' then
            rin.state <= ST_RX_DATA;
            rin.crc <= (others => crc_init(dat_crc_params_c));
            rin.base <= 8 - r.lane_count;
            rin.byte_left <= r.block_size_m1;
          elsif r.timeout = 0 then
            rin.state <= ST_DONE;
            rin.status <= DAT_TIMEOUT;
          else
            rin.timeout <= r.timeout - 1;
          end if;
        end if;

      when ST_RX_DATA =>
        if sample_i = '1' then
          rin.data <= merged;
          rin.crc <= crc_updated(r.crc, d_i, r.lane_count);

          if r.base /= 0 then
            rin.base <= r.base - r.lane_count;
          else
            rin.rx_valid <= '1';
            rin.rx_data <= merged;
            rin.base <= 8 - r.lane_count;

            if r.byte_left = 0 then
              rin.state <= ST_RX_CRC;
              rin.field_index <= 0;
            else
              rin.byte_left <= r.byte_left - 1;
            end if;
          end if;
        end if;

      when ST_RX_CRC =>
        if sample_i = '1' then
          rin.crc <= crc_updated(r.crc, d_i, r.lane_count);

          if r.field_index = crc_bit_count_c - 1 then
            rin.state <= ST_RX_END;
          else
            rin.field_index <= r.field_index + 1;
          end if;
        end if;

      when ST_RX_END =>
        if sample_i = '1' then
          rin.state <= ST_BLOCK_END;

          -- The checksum covers the block and the field that follows
          -- it, so the state left over once both are in tells whether
          -- the line carried them intact.
          if not crc_all_valid(r.crc, r.lane_count) then
            rin.status <= DAT_CRC_ERROR;
          elsif d_i(0) /= '1' then
            rin.status <= DAT_FRAMING_ERROR;
          end if;
        end if;

      when ST_TX_FETCH =>
        -- Between blocks a host may take as long as it likes, so the
        -- first byte is taken before anything goes on the wires.
        if tx_valid_i = '1' then
          rin.state <= ST_TX_START;
          rin.data <= tx_data_i;
          rin.crc <= (others => crc_init(dat_crc_params_c));
          rin.base <= 8 - r.lane_count;
          rin.byte_left <= r.block_size_m1;
        end if;

      when ST_TX_START =>
        if drive_i = '1' then
          rin.state <= ST_TX_DATA;
          rin.wire <= (others => '0');
          rin.driving <= '1';
        end if;

      when ST_TX_DATA =>
        if drive_i = '1' then
          rin.wire <= group_of(r.data, r.base, r.lane_count);
          rin.crc <= crc_updated(r.crc,
                                 group_of(r.data, r.base, r.lane_count),
                                 r.lane_count);

          if r.base /= 0 then
            rin.base <= r.base - r.lane_count;
          elsif r.byte_left = 0 then
            rin.state <= ST_TX_CRC;
            rin.field_index <= 0;
          elsif tx_valid_i = '1' then
            rin.data <= tx_data_i;
            rin.base <= 8 - r.lane_count;
            rin.byte_left <= r.byte_left - 1;
          else
            -- The block is lost either way: what is on the wires
            -- stops matching the checksum that will follow it.
            rin.state <= ST_DONE;
            rin.status <= DAT_UNDERRUN;
            rin.driving <= '0';
          end if;
        end if;

      when ST_TX_CRC =>
        if drive_i = '1' then
          rin.wire <= crc_group(r.crc, r.field_index, r.lane_count);

          if r.field_index = crc_bit_count_c - 1 then
            rin.state <= ST_TX_END;
          else
            rin.field_index <= r.field_index + 1;
          end if;
        end if;

      when ST_TX_END =>
        if drive_i = '1' then
          rin.state <= ST_TX_RELEASE;
          rin.wire <= (others => '1');
        end if;

      when ST_TX_RELEASE =>
        if drive_i = '1' then
          rin.state <= ST_TX_STATUS_WAIT;
          rin.driving <= '0';
          rin.timeout <= timeout_cycle_i;
        end if;

      when ST_TX_STATUS_WAIT =>
        if sample_i = '1' then
          if d_i(0) = '0' then
            rin.state <= ST_TX_STATUS;
            rin.data <= (others => '0');
            rin.field_index <= 0;
          elsif r.timeout = 0 then
            rin.state <= ST_DONE;
            rin.status <= DAT_TIMEOUT;
          else
            rin.timeout <= r.timeout - 1;
          end if;
        end if;

      when ST_TX_STATUS =>
        if sample_i = '1' then
          rin.data <= r.data(6 downto 0) & d_i(0);

          if r.field_index = 3 then
            rin.timeout <= timeout_cycle_i;
            rin.wait_cycle <= status_start_cycle_c;

            -- Three bits say what the card made of the block, and the
            -- end bit closes the token.
            case r.data(2 downto 0) is
              when "010" =>
                rin.state <= ST_TX_BUSY;

              when "101" =>
                rin.state <= ST_DONE;
                rin.status <= DAT_WRITE_REJECTED;

              when "110" =>
                rin.state <= ST_DONE;
                rin.status <= DAT_WRITE_FAILED;

              when others =>
                rin.state <= ST_DONE;
                rin.status <= DAT_FRAMING_ERROR;
            end case;

            if d_i(0) /= '1' then
              rin.state <= ST_DONE;
              rin.status <= DAT_FRAMING_ERROR;
            end if;
          else
            rin.field_index <= r.field_index + 1;
          end if;
        end if;

      when ST_TX_BUSY =>
        if sample_i = '1' then
          if r.wait_cycle /= 0 then
            rin.wait_cycle <= r.wait_cycle - 1;
          elsif d_i(0) = '1' then
            rin.state <= ST_BLOCK_END;
          elsif r.timeout = 0 then
            rin.state <= ST_DONE;
            rin.status <= DAT_TIMEOUT;
          else
            rin.timeout <= r.timeout - 1;
          end if;
        end if;

      when ST_BLOCK_END =>
        rin.block_done <= r.block_done + 1;
        rin.timeout <= timeout_cycle_i;

        if r.status /= DAT_OK then
          rin.state <= ST_DONE;
        elsif r.open_ended then
          if stop_i = '1' then
            rin.state <= ST_DONE;
          elsif r.write = '1' then
            rin.state <= ST_TX_FETCH;
          else
            rin.state <= ST_RX_WAIT;
          end if;
        elsif r.block_left = 1 then
          rin.state <= ST_DONE;
        else
          rin.block_left <= r.block_left - 1;

          if r.write = '1' then
            rin.state <= ST_TX_FETCH;
          else
            rin.state <= ST_RX_WAIT;
          end if;
        end if;

      when ST_DONE =>
        rin.state <= ST_IDLE;
    end case;

    if cancel_i = '1' and r.state /= ST_IDLE and r.state /= ST_DONE then
      rin.state <= ST_DONE;
      rin.status <= DAT_CANCELLED;
      rin.driving <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    -- Lines the host is not wired for do not exist, and those it is
    -- wired for but the bus is not using are left alone.
    for k in d_o'range
    loop
      if k < lane_count_c then
        if k < r.lane_count then
          d_o(k) <= nsl_io.io.to_tristated(r.wire(k), r.driving);
        else
          d_o(k) <= nsl_io.io.tristated_z;
        end if;
      else
        d_o(k) <= nsl_io.io.tristated_z;
      end if;
    end loop;

    req_o <= accept(r.state = ST_IDLE);

    case r.state is
      when ST_TX_BUSY =>
        busy_o <= '1';

      when others =>
        busy_o <= '0';
    end case;

    case r.state is
      when ST_DONE =>
        rsp_o.valid <= '1';

      when others =>
        rsp_o.valid <= '0';
    end case;

    rsp_o.status <= r.status;
    rsp_o.block_count <= r.block_done;

    rx_valid_o <= r.rx_valid;
    rx_data_o <= r.rx_data;
  end process;

  -- A block under way takes its next byte on the strobe that puts the
  -- last bits of the previous one on the wires, as the one after that
  -- already needs it.
  mealy: process(r, drive_i, tx_valid_i, rx_room_i) is
  begin
    tx_ready_o <= '0';
    stall_o <= '0';

    case r.state is
      when ST_TX_FETCH =>
        tx_ready_o <= '1';

      when ST_TX_DATA =>
        if r.base = 0 and r.byte_left /= 0 then
          if tx_valid_i = '1' then
            if drive_i = '1' then
              tx_ready_o <= '1';
            end if;
          else
            stall_o <= '1';
          end if;
        end if;

      when ST_RX_WAIT | ST_RX_DATA | ST_RX_CRC | ST_RX_END =>
        -- Held from anywhere in a read: what is read has nowhere to
        -- go, and so would the start of the next block.
        if rx_room_i = '0' then
          stall_o <= '1';
        end if;

      when others =>
        null;
    end case;
  end process;

end architecture;
