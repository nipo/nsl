library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.testing.all;

entity testing_card_model is
  generic(
    output_edge_c: nsl_sdio.link.card_output_edge_t
      := nsl_sdio.link.OUTPUT_ON_FALLING;
    output_delay_c: time := 14 ns;
    output_hold_c: time := 2500 ps;
    input_setup_c: time := 5 ns;
    response_delay_cycle_c: natural := 4;
    busy_cycle_c: natural := 12;
    data_delay_cycle_c: natural := 4;
    written_block_count_c: natural := 8;
    power_up_poll_count_c: natural := 3;
    cid_c: std_ulogic_vector(127 downto 8) := default_cid_c;
    block_count_c: natural := 65536
    );
  port(
    sdio_i: in nsl_sdio.sdio.sdio_slave_i;
    sdio_o: out nsl_sdio.sdio.sdio_slave_o
    );
end entity;

architecture beh of testing_card_model is

  -- Blocks of a card holding more than two gigabytes, which is the
  -- only size this model has.
  constant block_byte_count_c: natural := 512;

  -- States of the identification sequence, and the ones a transfer
  -- adds to them.  A card walks the first in order, and a reset
  -- command sends it back to the start.
  type card_state_t is (
    CARD_IDLE,
    CARD_READY,
    CARD_IDENT,
    CARD_STBY,
    CARD_TRAN,
    CARD_DATA,
    CARD_RCV,
    CARD_PRG
    );

  -- Relative address the card hands out.  A host has no say in it and
  -- learns it from the answer.
  constant rca_c: unsigned(15 downto 0) := x"1234";

  -- Operating conditions: the voltage window of a card fed at 3.3 V,
  -- high capacity addressing, and the bit that tells a host whether
  -- the card is done powering up.
  constant ocr_c: unsigned(31 downto 0) := x"40ff8000";

  function state_code(state: card_state_t) return unsigned
  is
  begin
    case state is
      when CARD_IDLE => return x"0";
      when CARD_READY => return x"1";
      when CARD_IDENT => return x"2";
      when CARD_STBY => return x"3";
      when CARD_TRAN => return x"4";
      when CARD_DATA => return x"5";
      when CARD_RCV => return x"6";
      when CARD_PRG => return x"7";
    end case;
  end function;

  type dat_op_t is (
    DAT_READ,
    DAT_WRITE
    );

  -- What the command engine hands the data engine, and how the two
  -- tell each other where a transfer stands.  A transfer is under way
  -- while the two counts differ.
  signal op_s: dat_op_t := DAT_READ;
  signal op_lba_s: unsigned(31 downto 0) := (others => '0');
  signal op_multiple_s: boolean := false;
  signal op_start_s: natural := 0;
  signal op_done_s: natural := 0;
  signal stop_s: std_ulogic := '0';

  -- Data lines the host switched the bus to
  signal width_s: bus_width_t := SDIO_WIDTH_1;

  signal dat_state_s: card_state_t := CARD_TRAN;

begin

  cmd: process is

    variable state: card_state_t;
    variable app_cmd: boolean;
    variable power_up_left: natural;
    variable op_count: natural;

    variable token: std_ulogic_vector(47 downto 0);
    variable index: natural;
    variable argument: unsigned(31 downto 0);
    variable acmd: boolean;

    -- Card status, as answered to most commands.  The state reported
    -- is the one the card was in when the command arrived, which is
    -- the data engine's while it has a transfer in hand.
    impure function status_word return unsigned
    is
      variable ret: unsigned(31 downto 0) := (others => '0');
    begin
      if op_start_s /= op_done_s then
        ret(12 downto 9) := state_code(dat_state_s);
      else
        ret(12 downto 9) := state_code(state);
      end if;
      -- Nothing here ever has a reason not to take data
      ret(8) := '1';
      if acmd then
        ret(5) := '1';
      end if;

      return ret;
    end function;

    -- A card reads what a host drives on the rising edge, whatever
    -- speed mode it is in, and checks it was there in time.
    procedure edge is
    begin
      wait until rising_edge(sdio_i.clk);

      assert sdio_i.cmd = sdio_i.cmd'delayed(input_setup_c)
        report "command line moved within the setup a card needs"
        severity failure;
    end procedure;

    -- The edge this card answers, which is where a value it drives
    -- starts counting from.
    procedure answered_edge is
    begin
      case output_edge_c is
        when nsl_sdio.link.OUTPUT_ON_FALLING =>
          wait until falling_edge(sdio_i.clk);

        when nsl_sdio.link.OUTPUT_ON_RISING =>
          wait until rising_edge(sdio_i.clk);
      end case;
    end procedure;

    procedure edges(count: natural) is
    begin
      for i in 1 to count
      loop
        edge;
      end loop;
    end procedure;

    -- Puts a value on the command line the way a card does: the
    -- previous one holds a little past the edge, then the wire says
    -- nothing until the card is done driving the new one.
    procedure drive_cmd(v: std_ulogic) is
    begin
      sdio_o.cmd <= nsl_io.io.to_tristated('X') after output_hold_c,
                    nsl_io.io.to_tristated(v) after output_delay_c;
    end procedure;

    procedure release_cmd is
    begin
      sdio_o.cmd <= nsl_io.io.to_tristated('X') after output_hold_c,
                    nsl_io.io.tristated_z after output_delay_c;
    end procedure;

    procedure respond(payload: std_ulogic_vector) is
    begin
      edges(response_delay_cycle_c);

      for i in payload'left downto payload'right
      loop
        answered_edge;
        drive_cmd(payload(i));
      end loop;

      answered_edge;
      release_cmd;
    end procedure;

    -- Hands a transfer to the data engine, which picks it up on its
    -- own and answers on the data lines while commands keep coming.
    procedure data_start(op: dat_op_t;
                         lba: unsigned;
                         multiple: boolean) is
    begin
      -- A stop stands until the next transfer is handed over, as
      -- nothing between the two pays attention to it.
      stop_s <= '0';
      op_s <= op;
      op_lba_s <= lba;
      op_multiple_s <= multiple;
      op_count := op_count + 1;
      op_start_s <= op_count;
    end procedure;

    procedure ignore(why: string) is
    begin
      report "card ignores CMD" & to_string(index) & ": " & why
        severity note;
    end procedure;

    procedure needs_data_phase is
    begin
      assert false
        report "CMD" & to_string(index)
        & " has a data phase, which this model does not have yet"
        severity failure;
    end procedure;

  begin
    sdio_o.cmd <= nsl_io.io.tristated_z;
    state := CARD_IDLE;
    app_cmd := false;
    power_up_left := power_up_poll_count_c;
    op_count := 0;

    loop
      -- A command opens with the only low bit a released line can
      -- carry.
      loop
        edge;
        exit when sdio_i.cmd = '0';
      end loop;

      token(47) := '0';
      for i in 46 downto 0
      loop
        edge;
        token(i) := sdio_i.cmd;
      end loop;

      index := to_integer(unsigned(token(45 downto 40)));
      argument := unsigned(token(39 downto 8));
      acmd := app_cmd;
      app_cmd := false;

      assert token(0) = '1'
        report "command has no end bit" severity failure;
      assert crc_is_valid(cmd_crc_params_c,
                          crc_update(cmd_crc_params_c,
                                     crc_init(cmd_crc_params_c),
                                     token(47 downto 8)),
                          token(7 downto 1))
        report "CMD" & to_string(index) & " has a bad checksum"
        severity failure;

      report "card got " & if_else(acmd, "ACMD", "CMD") & to_string(index)
        & " " & to_string(argument)
        severity note;

      if acmd then
        case index is
          when 6 =>
            -- SET_BUS_WIDTH
            if state /= CARD_TRAN then
              ignore("card is not selected");
            else
              case argument(1 downto 0) is
                when "00" =>
                  width_s <= SDIO_WIDTH_1;

                when "10" =>
                  width_s <= SDIO_WIDTH_4;

                when others =>
                  assert false
                    report "SET_BUS_WIDTH asks for a width no card has"
                    severity failure;
              end case;

              respond(short_response(6, std_ulogic_vector(status_word)));
            end if;

          when 41 =>
            -- SD_SEND_OP_COND, the one a host polls until the card is
            -- done powering up
            if state /= CARD_IDLE then
              ignore("card is past its idle state");
            elsif power_up_left /= 0 then
              power_up_left := power_up_left - 1;
              respond(short_response(63, std_ulogic_vector(ocr_c), false));
            else
              state := CARD_READY;
              respond(short_response(63,
                                     std_ulogic_vector(ocr_c or x"80000000"),
                                     false));
            end if;

          when 51 =>
            -- SEND_SCR
            needs_data_phase;

          when others =>
            ignore("unknown application command");
        end case;
      else
        case index is
          when 0 =>
            -- GO_IDLE_STATE, which no card answers
            state := CARD_IDLE;
            power_up_left := power_up_poll_count_c;
            width_s <= SDIO_WIDTH_1;

          when 2 =>
            -- ALL_SEND_CID
            if state = CARD_READY then
              state := CARD_IDENT;
              respond(long_response(card_register(cid_c)));
            else
              ignore("card is not waiting to be identified");
            end if;

          when 3 =>
            -- SEND_RELATIVE_ADDR
            if state = CARD_IDENT then
              -- What a card answers with is the state the command
              -- arrived in, so the move waits for the answer.
              respond(short_response(3,
                                     std_ulogic_vector(rca_c
                                                       & status_word(15 downto 0))));
              state := CARD_STBY;
            else
              ignore("card has no address to hand out yet");
            end if;

          when 5 =>
            -- IO_SEND_OP_COND, which a card holding memory only does
            -- not answer.  This is how a host tells the two apart.
            ignore("this card holds memory only");

          when 7 =>
            -- SELECT_CARD, and deselect when addressed to no card
            if argument(31 downto 16) = rca_c then
              respond(short_response(7, std_ulogic_vector(status_word)));
              state := CARD_TRAN;
            elsif state = CARD_TRAN then
              state := CARD_STBY;
            else
              ignore("another card is addressed");
            end if;

          when 8 =>
            -- SEND_IF_COND, answered by echoing what was asked
            if state = CARD_IDLE then
              respond(short_response(8, std_ulogic_vector(argument)));
            else
              ignore("card is past its idle state");
            end if;

          when 9 =>
            -- SEND_CSD
            if argument(31 downto 16) = rca_c then
              respond(long_response(csd_v2(block_count_c)));
            else
              ignore("another card is addressed");
            end if;

          when 10 =>
            -- SEND_CID
            if argument(31 downto 16) = rca_c then
              respond(long_response(card_register(cid_c)));
            else
              ignore("another card is addressed");
            end if;

          when 12 =>
            -- STOP_TRANSMISSION, which ends a transfer that was given
            -- no block count.  The data engine finishes the block it
            -- has in hand, which is why the answer goes out while it
            -- is still busy.
            if state /= CARD_TRAN then
              ignore("card is not selected");
            else
              -- The data engine finishes the block it has in hand on
              -- its own, and answering this does not wait for it: a
              -- card takes commands while a block is still going out.
              stop_s <= '1';
              respond(short_response(12, std_ulogic_vector(status_word)));
            end if;

          when 13 =>
            -- SEND_STATUS
            if argument(31 downto 16) = rca_c then
              respond(short_response(13, std_ulogic_vector(status_word)));
            else
              ignore("another card is addressed");
            end if;

          when 16 =>
            -- SET_BLOCKLEN, which a card holding more than two
            -- gigabytes takes but does not act on
            if state /= CARD_TRAN then
              ignore("card is not selected");
            else
              assert argument = block_byte_count_c
                report "SET_BLOCKLEN asks for " & to_string(argument)
                & " bytes, which a high capacity card cannot do"
                severity failure;
              respond(short_response(16, std_ulogic_vector(status_word)));
            end if;

          when 17 | 18 =>
            -- READ_SINGLE_BLOCK and READ_MULTIPLE_BLOCK
            if state /= CARD_TRAN then
              ignore("card is not selected");
            elsif op_start_s /= op_done_s then
              ignore("a transfer is already under way");
            else
              respond(short_response(index, std_ulogic_vector(status_word)));
              data_start(DAT_READ, argument, index = 18);
            end if;

          when 24 | 25 =>
            -- WRITE_BLOCK and WRITE_MULTIPLE_BLOCK
            if state /= CARD_TRAN then
              ignore("card is not selected");
            elsif op_start_s /= op_done_s then
              ignore("a transfer is already under way");
            else
              respond(short_response(index, std_ulogic_vector(status_word)));
              data_start(DAT_WRITE, argument, index = 25);
            end if;

          when 55 =>
            -- APP_CMD, which turns the next command into its
            -- application specific twin
            app_cmd := true;
            acmd := true;
            respond(short_response(55, std_ulogic_vector(status_word)));

          when 6 =>
            needs_data_phase;

          when others =>
            ignore("unknown command");
        end case;
      end if;
    end loop;
  end process;

  dat: process is

    type store_entry_t is
    record
      valid: boolean;
      lba: unsigned(31 downto 0);
      data: byte_string(0 to block_byte_count_c - 1);
    end record;

    type store_t is array (0 to written_block_count_c - 1) of store_entry_t;

    variable store: store_t;
    variable lba: unsigned(31 downto 0);
    variable done: natural;
    variable buf: byte_string(0 to block_byte_count_c - 1);
    variable status: std_ulogic_vector(2 downto 0);
    variable aborted: boolean;

    procedure edge is
    begin
      wait until rising_edge(sdio_i.clk);
    end procedure;

    procedure edges(count: natural) is
    begin
      for i in 1 to count
      loop
        edge;
      end loop;
    end procedure;

    -- The edge this card answers, as on the command line
    procedure answered_edge is
    begin
      case output_edge_c is
        when nsl_sdio.link.OUTPUT_ON_FALLING =>
          wait until falling_edge(sdio_i.clk);

        when nsl_sdio.link.OUTPUT_ON_RISING =>
          wait until rising_edge(sdio_i.clk);
      end case;
    end procedure;

    procedure drive_lanes(v: std_ulogic_vector) is
    begin
      for k in 0 to lane_count(width_s) - 1
      loop
        sdio_o.d(k) <= nsl_io.io.to_tristated('X') after output_hold_c,
                       nsl_io.io.to_tristated(v(k)) after output_delay_c;
      end loop;
    end procedure;

    procedure release_lanes is
    begin
      for k in 0 to lane_count(width_s) - 1
      loop
        sdio_o.d(k) <= nsl_io.io.to_tristated('X') after output_hold_c,
                       nsl_io.io.tristated_z after output_delay_c;
      end loop;
    end procedure;

    -- The status token and the busy that follows it travel on DAT0
    -- alone, whatever the bus was switched to.
    procedure drive_dat0(v: std_ulogic) is
    begin
      sdio_o.d(0) <= nsl_io.io.to_tristated('X') after output_hold_c,
                     nsl_io.io.to_tristated(v) after output_delay_c;
    end procedure;

    procedure release_dat0 is
    begin
      sdio_o.d(0) <= nsl_io.io.to_tristated('X') after output_hold_c,
                     nsl_io.io.tristated_z after output_delay_c;
    end procedure;

    procedure store_write(lba: unsigned; data: byte_string) is
      variable slot: integer := -1;
    begin
      for i in store'range
      loop
        if store(i).valid and store(i).lba = lba then
          slot := i;
        end if;
      end loop;

      if slot < 0 then
        for i in store'reverse_range
        loop
          if not store(i).valid then
            slot := i;
          end if;
        end loop;
      end if;

      assert slot >= 0
        report "model has no room left to remember written blocks"
        severity failure;

      store(slot).valid := true;
      store(slot).lba := lba;
      store(slot).data := data;
    end procedure;

    -- What a block reads back: what was written to it, or what its
    -- address says it holds.
    impure function store_read(lba: unsigned) return byte_string is
    begin
      for i in store'range
      loop
        if store(i).valid and store(i).lba = lba then
          return store(i).data;
        end if;
      end loop;

      return default_block(lba, block_byte_count_c);
    end function;

    procedure send_block(data: byte_string) is
      constant lane_count_c: natural := lane_count(width_s);
      constant bit_count_c: natural := data'length * 8 / lane_count_c;

      type lane_bits_t is array (natural range <>)
        of std_ulogic_vector(0 to bit_count_c - 1);
      type lane_crc_t is array (natural range <>)
        of std_ulogic_vector(15 downto 0);

      variable bits: lane_bits_t(0 to lane_count_c - 1);
      variable crc: lane_crc_t(0 to lane_count_c - 1);
      variable wire: std_ulogic_vector(max_lane_count_c - 1 downto 0);
    begin
      for k in bits'range
      loop
        bits(k) := to_lane_bits(data, width_s, k);
        crc(k) := lane_crc(bits(k));
      end loop;

      wire := (others => '0');
      answered_edge;
      drive_lanes(wire);

      for i in 0 to bit_count_c - 1
      loop
        for k in bits'range
        loop
          wire(k) := bits(k)(i);
        end loop;

        answered_edge;
        drive_lanes(wire);
      end loop;

      for b in 15 downto 0
      loop
        for k in crc'range
        loop
          wire(k) := crc(k)(b);
        end loop;

        answered_edge;
        drive_lanes(wire);
      end loop;

      wire := (others => '1');
      answered_edge;
      drive_lanes(wire);

      answered_edge;
      release_lanes;
    end procedure;

    -- Takes a block off the wires, says what it made of it, then
    -- holds DAT0 low the way a card does while storing it.
    procedure recv_block(data: inout byte_string;
                         status: out std_ulogic_vector;
                         aborted: out boolean) is
      variable verdict: std_ulogic_vector(2 downto 0) := "010";
      constant lane_count_c: natural := lane_count(width_s);
      constant bit_count_c: natural := data'length * 8 / lane_count_c;

      type lane_bits_t is array (natural range <>)
        of std_ulogic_vector(0 to bit_count_c - 1);
      type lane_crc_t is array (natural range <>)
        of std_ulogic_vector(15 downto 0);

      variable bits: lane_bits_t(0 to lane_count_c - 1);
      variable crc: lane_crc_t(0 to lane_count_c - 1);
      variable intact: boolean := true;
    begin
      aborted := false;

      loop
        edge;
        exit when sdio_i.d(0) = '0';

        if stop_s = '1' then
          aborted := true;
          return;
        end if;
      end loop;

      for i in 0 to bit_count_c - 1
      loop
        edge;

        for k in bits'range
        loop
          bits(k)(i) := sdio_i.d(k);
        end loop;
      end loop;

      for b in 15 downto 0
      loop
        edge;

        for k in crc'range
        loop
          crc(k)(b) := sdio_i.d(k);
        end loop;
      end loop;

      edge;
      assert sdio_i.d(0) = '1'
        report "block did not end where a block ends" severity failure;

      for k in bits'range
      loop
        if crc(k) /= lane_crc(bits(k)) then
          intact := false;
        end if;
      end loop;

      if intact then
        for k in bits'range
        loop
          lane_bits_merge(data, bits(k), width_s, k);
        end loop;
      else
        verdict := "101";
      end if;

      status := verdict;

      -- Start bit, three bits saying what the card made of the block,
      -- end bit, and then the card is busy with it.
      answered_edge;
      drive_dat0('0');

      for i in 2 downto 0
      loop
        answered_edge;
        drive_dat0(verdict(i));
      end loop;

      answered_edge;
      drive_dat0('1');

      answered_edge;
      drive_dat0('0');
      edges(busy_cycle_c);
      release_dat0;
    end procedure;

  begin
    for k in 0 to max_lane_count_c - 1
    loop
      sdio_o.d(k) <= nsl_io.io.tristated_z;
    end loop;

    store := (others => (valid => false,
                         lba => (others => '0'),
                         data => (others => x"00")));
    done := 0;

    loop
      while op_start_s = done
      loop
        wait on op_start_s;
      end loop;

      lba := op_lba_s;

      case op_s is
        when DAT_READ =>
          dat_state_s <= CARD_DATA;
          edges(data_delay_cycle_c);

          loop
            send_block(store_read(lba));
            lba := lba + 1;
            exit when not op_multiple_s;
            exit when stop_s = '1';
          end loop;

        when DAT_WRITE =>
          dat_state_s <= CARD_RCV;

          loop
            recv_block(buf, status, aborted);
            exit when aborted;

            if status = "010" then
              store_write(lba, buf);
            end if;

            lba := lba + 1;
            exit when not op_multiple_s;
            exit when stop_s = '1';
          end loop;
      end case;

      dat_state_s <= CARD_TRAN;
      done := op_start_s;
      op_done_s <= done;
    end loop;
  end process;

end architecture;
