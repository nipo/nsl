library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_simulation, nsl_data, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.cbor.all;
use nsl_data.text.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.cbor_transactor.all;
use nsl_sdio.testing.all;

-- Runs a host driven by a command stream against a card model, over
-- the identification sequence and a block read, and checks what comes
-- back byte for byte.
entity tb is
end entity;

architecture beh of tb is

  constant clock_i_hz_c: natural := 100000000;
  constant clock_period_c: time := 10 ns;
  constant block_byte_count_c: natural := 512;

  constant stream_cfg_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => 1, last => true);

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal cmd_s: nsl_amba.axi4_stream.master_t;
  signal cmd_ack_s: nsl_amba.axi4_stream.slave_t;
  signal rsp_s: nsl_amba.axi4_stream.master_t;
  signal rsp_ack_s: nsl_amba.axi4_stream.slave_t;

  signal present_s: std_ulogic := '0';

  signal bus_o_s: sdio_master_o;
  signal bus_i_s: sdio_master_i;
  signal card_o_s: sdio_slave_o;
  signal bus_s: sdio_bus;

  -- What came back, and how much of it
  constant rsp_max_c: natural := 2048;
  signal rsp_buf_s: byte_string(0 to rsp_max_c - 1);
  signal rsp_count_s: natural := 0;
  signal rsp_reset_s: std_ulogic := '0';

  -- Bus settings the identification sequence runs with, faster than a
  -- bus is allowed to start so that the test stays short.
  constant half_cycle_c: natural := half_cycle_m1(clock_i_hz_c, 2000000);
  constant phase_c: natural := default_sample_phase(clock_i_hz_c, half_cycle_c);

  -- What a card takes without being asked, where a bus period is a
  -- couple of fabric cycles and a host has no room to dawdle
  constant fast_half_cycle_c: natural
    := half_cycle_m1(clock_i_hz_c, 25000000);
  constant fast_phase_c: natural
    := default_sample_phase(clock_i_hz_c, fast_half_cycle_c);

begin

  clock_s <= (not clock_s) after clock_period_c / 2 when not done_s else '0';
  reset_n_s <= '1' after 3 * clock_period_c;

  bus_s <= to_bus(bus_o_s);
  bus_s <= to_bus(card_o_s);
  bus_s <= sdio_bus_released_c;

  bus_i_s <= to_master_i(bus_s);

  dut: nsl_sdio.cbor_transactor.axi4stream_cbor_sdio_transactor
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      stream_config_c => stream_cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sdio_o => bus_o_s,
      sdio_i => bus_i_s,

      card_present_i => present_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      rsp_o => rsp_s,
      rsp_i => rsp_ack_s
      );

  card: nsl_sdio.testing.testing_card_model
    port map(
      sdio_i => to_slave_i(bus_s),
      sdio_o => card_o_s
      );

  rsp_ack_s <= nsl_amba.axi4_stream.accept(stream_cfg_c, true);

  collector: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if rsp_reset_s = '1' then
        rsp_count_s <= 0;
      elsif nsl_amba.axi4_stream.is_valid(stream_cfg_c, rsp_s) then
        assert rsp_count_s < rsp_max_c
          report "more came back than the test has room for"
          severity failure;
        rsp_buf_s(rsp_count_s) <= rsp_s.data(0);
        rsp_count_s <= rsp_count_s + 1;
      end if;
    end if;
  end process;

  stim: process is

    -- Values as the encoding spells them out
    function u5(v: natural) return byte_string
    is
    begin
      return from_suv(std_ulogic_vector(to_unsigned(v, 8)));
    end function;

    function u8(v: natural) return byte_string
    is
    begin
      return from_hex("18") & from_suv(std_ulogic_vector(to_unsigned(v, 8)));
    end function;

    -- One command, as the encoding has it
    function sd_command(response: natural;
                        index: natural;
                        argument: unsigned) return byte_string
    is
    begin
      return cbor_tag_hdr(cmd_tag_command_c)
        & cbor_array_hdr(length => 3)
        & cbor_positive(response)
        & cbor_positive(index)
        & cbor_positive(argument);
    end function;

    function sd_read(response: natural;
                     index: natural;
                     argument: unsigned;
                     block_size: natural;
                     block_count: natural) return byte_string
    is
    begin
      return cbor_tag_hdr(cmd_tag_read_c)
        & cbor_array_hdr(length => 5)
        & cbor_positive(response)
        & cbor_positive(index)
        & cbor_positive(argument)
        & cbor_positive(block_size)
        & cbor_positive(block_count);
    end function;

    function sd_write(response: natural;
                      index: natural;
                      argument: unsigned;
                      block_size: natural;
                      data: byte_string) return byte_string
    is
    begin
      return cbor_tag_hdr(cmd_tag_write_c)
        & cbor_array_hdr(length => 5)
        & cbor_positive(response)
        & cbor_positive(index)
        & cbor_positive(argument)
        & cbor_positive(block_size)
        & cbor_bstr_hdr(length => to_unsigned(data'length, 16))
        & data;
    end function;

    function sd_repeat(body_count: natural;
                       attempts: natural;
                       mask: unsigned;
                       match: unsigned) return byte_string
    is
    begin
      return cbor_tag_hdr(cmd_tag_repeat_c)
        & cbor_array_hdr(length => 4)
        & cbor_positive(body_count)
        & cbor_positive(attempts)
        & cbor_positive(mask)
        & cbor_positive(match);
    end function;

    function event_item(kind: natural; asserted: boolean) return byte_string
    is
      variable flag: byte_string(0 to 0);
    begin
      if asserted then
        flag(0) := x"f5";
      else
        flag(0) := x"f4";
      end if;

      return cbor_tag_hdr(rsp_tag_event_c)
        & cbor_array_hdr(length => 2)
        & u5(kind)
        & flag;
    end function;

    function setting(tag: natural; value: natural) return byte_string
    is
    begin
      return cbor_tag_hdr(tag) & cbor_positive(value);
    end function;

    -- What a command that went through answers with
    function command_rsp(status: natural;
                         index: natural;
                         payload: byte_string) return byte_string
    is
    begin
      return cbor_tag_hdr(rsp_tag_command_c)
        & cbor_array_hdr(length => 3)
        & u5(status) & u8(index)
        & cbor_bstr_hdr(length => to_unsigned(payload'length, 8))
        & payload;
    end function;

    -- Data of a read, as it comes out: a chunk per block, so a run
    -- that dies on its third block puts out two and then says why.
    function chunked(data: byte_string; block_size: natural)
      return byte_string
    is
      constant blocks_c: natural := data'length / block_size;
      variable ret: byte_string(0 to data'length + 3 * blocks_c - 1);
      variable at: natural := 0;
    begin
      for i in 0 to blocks_c - 1
      loop
        ret(at to at + 2) := cbor_bstr_hdr(length => to_unsigned(block_size, 12));
        at := at + 3;
        ret(at to at + block_size - 1)
          := data(data'low + i * block_size to data'low + (i + 1) * block_size - 1);
        at := at + block_size;
      end loop;

      return ret(0 to at - 1);
    end function;

    function read_rsp(status: natural;
                      index: natural;
                      payload: byte_string;
                      block_size: natural;
                      data: byte_string;
                      dat_status: natural;
                      blocks: natural) return byte_string
    is
    begin
      return cbor_tag_hdr(rsp_tag_read_c)
        & cbor_array_hdr(length => 6)
        & u5(status) & u8(index)
        & cbor_bstr_hdr(length => to_unsigned(payload'length, 8))
        & payload
        & from_hex("5f")
        & chunked(data, block_size)
        & from_hex("ff")
        & u5(dat_status)
        & from_hex("1a")
        & from_suv(std_ulogic_vector(to_unsigned(blocks, 32)));
    end function;

    function write_rsp(status: natural;
                       index: natural;
                       payload: byte_string;
                       dat_status: natural;
                       blocks: natural) return byte_string
    is
    begin
      return cbor_tag_hdr(rsp_tag_write_c)
        & cbor_array_hdr(length => 5)
        & u5(status) & u8(index)
        & cbor_bstr_hdr(length => to_unsigned(payload'length, 8))
        & payload
        & u5(dat_status)
        & from_hex("1a")
        & from_suv(std_ulogic_vector(to_unsigned(blocks, 32)));
    end function;

    constant ack_c: byte_string := cbor_tag_hdr(rsp_tag_ack_c) & from_hex("f6");

    -- A block of something a card would not hold by itself
    impure function written_block return byte_string
    is
      variable ret: byte_string(0 to block_byte_count_c - 1);
    begin
      for i in ret'range
      loop
        ret(i) := std_ulogic_vector(to_unsigned((i * 7 + 19) mod 256, 8));
      end loop;

      return ret;
    end function;

    constant written_c: byte_string := written_block;

    -- A second block, so that a run of them says which is which
    impure function other_block return byte_string
    is
      variable ret: byte_string(0 to block_byte_count_c - 1);
    begin
      for i in ret'range
      loop
        ret(i) := std_ulogic_vector(to_unsigned((i * 11 + 71) mod 256, 8));
      end loop;

      return ret;
    end function;

    constant other_c: byte_string := other_block;
    -- Card status of a selected card with nothing to complain about
    constant tran_c: byte_string := from_hex("00000900");
    -- The same, while taking a run of blocks, and while sending one:
    -- what a command answers with is where a card was when it arrived
    constant rcv_c: byte_string := from_hex("00000d00");
    constant sending_c: byte_string := from_hex("00000b00");
    constant empty_c: byte_string(0 to -1) := (others => x"00");

    -- A command stream with gaps in it, which is what one carried
    -- over a bus with a life of its own looks like: the blocks of a
    -- write arrive as fast as whatever is upstream hands them over,
    -- and a write already under way has to wait for them where it
    -- stands.
    procedure send(data: byte_string;
                   gap: natural := 0;
                   every: positive := 1) is
    begin
      for i in data'range
      loop
        if gap /= 0 and (i - data'low) mod every = 0 then
          for g in 1 to gap
          loop
            cmd_s <= nsl_amba.axi4_stream.transfer_defaults(stream_cfg_c);
            wait until rising_edge(clock_s);
          end loop;
        end if;

        cmd_s <= nsl_amba.axi4_stream.transfer(
          stream_cfg_c,
          bytes => (0 => data(i)),
          valid => true,
          last => i = data'right);

        loop
          wait until rising_edge(clock_s);
          exit when nsl_amba.axi4_stream.is_ready(stream_cfg_c, cmd_ack_s);
        end loop;
      end loop;

      cmd_s <= nsl_amba.axi4_stream.transfer_defaults(stream_cfg_c);
    end procedure;

    procedure check(want: byte_string; what: string) is
      variable bad: natural := 0;
    begin
      loop
        wait until rising_edge(clock_s);
        exit when rsp_count_s >= want'length;
      end loop;

      wait for 20 * clock_period_c;

      assert rsp_count_s = want'length
        report what & " answered " & to_string(rsp_count_s)
        & " bytes instead of " & to_string(want'length)
        severity failure;

      for i in 0 to want'length - 1
      loop
        if rsp_buf_s(i) /= want(want'low + i) then
          if bad = 0 then
            report what & " byte " & to_string(i) & " came back as "
              & to_string(rsp_buf_s(i)) & " instead of "
              & to_string(want(want'low + i))
              severity failure;
          end if;
          bad := bad + 1;
        end if;
      end loop;

      assert bad = 0
        report to_string(bad) & " bytes of " & what & " differ"
        severity failure;
    end procedure;

    -- One batch, and what it is expected to answer
    procedure batch(commands: byte_string;
                    want: byte_string;
                    what: string;
                    gap: natural := 0;
                    every: positive := 1) is
    begin
      rsp_reset_s <= '1';
      wait until rising_edge(clock_s);
      rsp_reset_s <= '0';

      report what severity note;
      send(from_hex("9f") & commands & from_hex("ff"), gap, every);
      check(from_hex("9f") & want & from_hex("ff"), what);
    end procedure;

  begin
    cmd_s <= nsl_amba.axi4_stream.transfer_defaults(stream_cfg_c);
    wait until reset_n_s = '1';

    -- What this host is made of, which is all it can answer before a
    -- card is involved.
    batch(from_hex("e2"),
          cbor_tag_hdr(rsp_tag_info_c)
          & cbor_array_hdr(length => 4)
          & cbor_positive(spec_version_c)
          & cbor_positive(clock_i_hz_c)
          & cbor_positive(4)
          & cbor_positive(4096),
          "info");

    -- A delay of its own, at the speed a card is identified at, which
    -- is the slowest the bus ever runs and the one a host gives a
    -- card its first clocks at.
    batch(setting(cmd_tag_half_cycle_c,
                  half_cycle_m1(clock_i_hz_c, 400000))
          & setting(cmd_tag_sample_phase_c,
                    default_sample_phase(clock_i_hz_c,
                                         half_cycle_m1(clock_i_hz_c, 400000)))
          & cbor_positive(4),
          ack_c & ack_c & ack_c,
          "clocks before a card is spoken to");

    -- The same, as a batch of its own: a host that has nothing else
    -- to say waits that way.
    batch(cbor_positive(4), ack_c, "clocks on their own");

    -- A bus faster than one is allowed to start, so the test stays
    -- short, then the two commands every card takes first.
    batch(setting(cmd_tag_half_cycle_c, half_cycle_c)
          & setting(cmd_tag_sample_phase_c, phase_c)
          & cbor_positive(400)
          & sd_command(0, 0, x"00000000")
          & sd_command(1, 8, x"000001aa"),
          ack_c & ack_c & ack_c
          & command_rsp(0, 0, empty_c)
          & command_rsp(0, 8, from_hex("000001aa")),
          "reset and interface condition");

    -- Polled until the card says it is done powering up, which the
    -- model takes a few answers to say.  Two commands make the body,
    -- as the answer carrying operating conditions only follows the
    -- one saying what comes next is application specific, and that
    -- answer has ones where a checksum would be, hence the kind that
    -- does not check it.
    --
    -- The whole loop answers once, with what its last command got in
    -- its last round.
    batch(sd_repeat(2, 10, x"80000000", x"80000000")
          & sd_command(1, 55, x"00000000")
          & sd_command(2, 41, x"40ff8000"),
          command_rsp(0, 63, from_hex("c0ff8000")),
          "operating conditions");

    -- Identification proper: the card's own registers, the address it
    -- hands out, and being selected.
    batch(sd_command(4, 2, x"00000000")
          & sd_command(1, 3, x"00000000")
          & sd_command(4, 9, x"12340000")
          & sd_command(3, 7, x"12340000"),
          command_rsp(0, 63, from_suv(card_register(default_cid_c)))
          & command_rsp(0, 3, from_hex("12340500"))
          & command_rsp(0, 63, from_suv(csd_v2(65536)))
          & command_rsp(0, 7, from_hex("00000700")),
          "identification");

    -- Four data lines, and blocks of the only size a card of this
    -- size has.
    batch(sd_command(1, 16, x"00000200")
          & sd_command(1, 55, x"12340000")
          & sd_command(1, 6, x"00000002")
          & setting(cmd_tag_width_c, 4),
          command_rsp(0, 16, tran_c)
          & command_rsp(0, 55, from_hex("00000920"))
          & command_rsp(0, 6, from_hex("00000920"))
          & ack_c,
          "bus width");

    batch(sd_read(1, 17, x"00001000", block_byte_count_c, 1),
          read_rsp(0, 17, tran_c, block_byte_count_c,
                   default_block(x"00001000", block_byte_count_c), 0, 1),
          "one block read");

    -- Written, then read back: what a card holds is what was put
    -- there, and the bytes went out of the command stream into the
    -- blocks without anything holding a copy.
    batch(sd_write(1, 24, x"00002000", block_byte_count_c, written_c),
          write_rsp(0, 24, tran_c, 0, 1),
          "one block written");

    batch(sd_read(1, 17, x"00002000", block_byte_count_c, 1),
          read_rsp(0, 17, tran_c, block_byte_count_c, written_c, 0, 1),
          "written block read back");

    -- A bus as fast as a card takes without being asked, where a
    -- byte of a block is a couple of bus periods rather than the
    -- leisurely stretch the rest of this runs at.
    batch(setting(cmd_tag_half_cycle_c, fast_half_cycle_c)
          & setting(cmd_tag_sample_phase_c, fast_phase_c),
          ack_c & ack_c,
          "default speed");

    -- A run of blocks, handed over more slowly than the bus takes
    -- them.  A card clocks its side of a block out whatever a host
    -- does, so the only way to make one wait is to take its clock
    -- away, and what a host does with the bit it was holding when it
    -- did is what this is about.
    batch(sd_write(1, 25, x"00003000", block_byte_count_c,
                   written_c & other_c)
          & sd_command(3, 12, x"00000000"),
          write_rsp(0, 25, tran_c, 0, 2)
          & command_rsp(0, 12, rcv_c),
          "blocks written as they come",
          gap => 300, every => 37);

    batch(sd_read(1, 18, x"00003000", block_byte_count_c, 2)
          & sd_command(3, 12, x"00000000"),
          read_rsp(0, 18, tran_c, block_byte_count_c,
                   written_c & other_c, 0, 2)
          & command_rsp(0, 12, sending_c),
          "blocks read back");

    -- A loop of one command, waiting on a field of what a card
    -- answers rather than on the answer itself: this is how a host
    -- waits for a card to be done with what it was given.
    batch(sd_repeat(1, 100, x"00001e00", x"00000800")
          & sd_command(1, 13, x"12340000"),
          command_rsp(0, 13, tran_c),
          "poll until the card takes data again");

    -- A loop that never gets what it waits for ends the batch: what
    -- follows it is not run, and what it answers with is the last
    -- thing it got.
    batch(sd_repeat(1, 2, x"00000000", x"00000000")
          & sd_command(1, 13, x"43210000")
          & sd_command(1, 13, x"12340000"),
          command_rsp(1, 0, from_hex("00000000")),
          "a loop that runs out of attempts");

    -- Events, which say where a line stands rather than what it did,
    -- and which land on their own while no batch is running.
    batch(setting(cmd_tag_events_c, 6), ack_c, "events asked for");

    rsp_reset_s <= '1';
    wait until rising_edge(clock_s);
    rsp_reset_s <= '0';
    present_s <= '1';
    check(event_item(1, true), "a card put in");

    rsp_reset_s <= '1';
    wait until rising_edge(clock_s);
    rsp_reset_s <= '0';
    present_s <= '0';
    check(event_item(2, false), "a card taken out");

    report "sdio cbor transactor test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
