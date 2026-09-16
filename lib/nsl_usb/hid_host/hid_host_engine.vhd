library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking, nsl_data, nsl_math, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_usb.usb.all;
use nsl_usb.ukp.all;
use nsl_usb.hid_host.all;

-- Microcoded full-/low-speed USB host sequencer, running the program given
-- as a generic through the instruction set of the ukp package.
--
-- The sequencer alternates a fetch cycle and an execute cycle: the ROM
-- is read with the program counter as registered address, and the word
-- lands in a register one cycle later.  An instruction that cannot
-- complete yet (START, OUT0, HIZ, IN, WAIT) leaves the program counter
-- and the instruction register untouched, so it re-executes with its
-- operand still available until its condition clears.  Output
-- instructions retire immediately and hand a byte to the serializer;
-- the instruction stream then idles until the serializer is done.
--
-- Bit timing follows the selected speed. While the driver is released,
-- transitions realign the receiver's mid-bit sample point.
entity hid_host_engine is
  generic(
    program_c: program_t;
    clock_rate_c: natural := 12_000_000;
    -- Whether to carry the logic for talking to full-speed devices.
    -- It costs a faster clock -- a full-speed bit has to be several
    -- cycles long, where a low-speed one is eight times that -- and
    -- so is worth declining where only low-speed devices are
    -- expected.  A host built without it sees a full-speed device as
    -- an empty port.
    full_speed_c: boolean := false
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    bus_o: out nsl_usb.io.usb_io_c;
    bus_i: in nsl_usb.io.usb_io_s;

    identity_o: out device_identity_t;
    status_o: out hid_host_status_t;

    report_o: out nsl_amba.axi4_stream.master_t;
    report_i: in nsl_amba.axi4_stream.slave_t
    );
begin

  assert clock_rate_c mod 1_500_000 = 0 and clock_rate_c >= 12_000_000
    report "hid_host_engine needs a multiple of 1.5MHz, 12MHz or more: a "
    & "low-speed bit is a whole number of cycles and wants at least eight "
    & "of them"
    severity failure;

  assert not full_speed_c
    or (clock_rate_c mod 12_000_000 = 0 and clock_rate_c >= 48_000_000)
    report "a full-speed capable hid_host_engine needs a multiple of 12MHz, "
    & "48MHz or more: a full-speed bit is clock_rate_c/12MHz cycles and the "
    & "receiver wants at least four of them to find the middle of one"
    severity failure;

end entity;

architecture beh of hid_host_engine is

  constant rom_c: rom_t := assemble(program_c);

  -- Instruction word address space of the ISA.
  constant pc_width_c: natural := 11;

  -- Cycles in a bit time, one speed each.  Full speed is 12Mb/s and
  -- low speed an eighth of that, so the two differ by a factor of
  -- eight and nothing else about the wire differs at all.
  -- Zero when the clock is too slow to carry a full-speed bit, which
  -- only happens where full speed was not asked for.
  constant fs_bit_cycles_c: natural := clock_rate_c / 12_000_000;
  constant ls_bit_cycles_c: natural := clock_rate_c / 1_500_000;
  constant t_width_c: natural := nsl_math.arith.log2(ls_bit_cycles_c);

  constant ms_last_c: natural := clock_rate_c / 1000 - 1;

  -- Slightly more than a second.
  constant wd_width_c: natural := nsl_math.arith.log2(clock_rate_c);
  constant wd_last_c: unsigned(wd_width_c - 1 downto 0) := (others => '1');

  -- Longest packet the receive buffer keeps, and its CRC16.  A report
  -- is bounded by the low-speed packet size; a control transfer is
  -- bounded by what the program asks for, since a device may answer
  -- the whole of it at once.
  constant rx_buffer_size_c: natural
    := nsl_math.arith.max(report_length_max_c, control_length_max_c) + 2;

  constant op_speed_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_SPEED);
  constant op_bfs_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BFS);
  constant op_sof_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_SOF);
  constant op_control_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_CONTROL);
  constant op_bmore_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BMORE);
  constant op_ldi_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_LDI);
  constant op_start_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_START);
  constant op_out4_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_OUT4);
  constant op_out0_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_OUT0);
  constant op_hiz_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_HIZ);
  constant op_outb_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_OUTB);
  constant op_ret_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_RET);
  constant op_bz_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BZ);
  constant op_bc_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BC);
  constant op_bnak_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BNAK);
  constant op_berr_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_BERR);
  constant op_djnz_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_DJNZ);
  constant op_toggle_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_TOGGLE);
  constant op_save_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_SAVE);
  constant op_in_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_IN);
  constant op_wait_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_WAIT);
  constant op_jmp_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_JMP);
  constant op_call_c: std_ulogic_vector(4 downto 0) := opcode_encode(UKP_CALL);

  subtype pc_t is unsigned(pc_width_c - 1 downto 0);

  type identity_regs_t is array (0 to save_reg_ep0_mps_c) of byte;

  type regs_t is
  record
    -- Sequencer.
    pc: pc_t;
    link: pc_t;
    inst: word_t;
    inst_ready: std_ulogic;
    w: unsigned(10 downto 0);
    c: std_ulogic;
    nak: std_ulogic;
    err: std_ulogic;

    -- Bit timer and free-running millisecond timer.
    t: unsigned(t_width_c - 1 downto 0);
    ms_count: natural range 0 to ms_last_c;

    -- What the device turned out to be, latched by SPEED.  It sets
    -- the bit period and swaps the lines; nothing else depends on it.
    full_speed: std_ulogic;
    -- Frame number of the next start-of-frame token.  Full speed
    -- only: low speed has no frames, only bare end-of-packet
    -- keep-alives.
    frame_no: unsigned(10 downto 0);

    -- Line driver.
    dp: std_ulogic;
    dm: std_ulogic;
    oe: std_ulogic;
    dm_prev: std_ulogic;

    -- Transmitter.
    tx_data: byte;
    tx_index: natural range 0 to 7;
    tx_nrzi: boolean;
    tx_active: std_ulogic;
    tx_ones: natural range 0 to 6;

    -- Receiver.
    rx_prev: std_ulogic;
    rx_shift: byte;
    rx_bit: natural range 0 to 7;
    -- 0 while assembling SYNC, 1 while assembling the PID, 2 from the
    -- first payload byte on.
    rx_index: natural range 0 to 2;
    rx_ones: natural range 0 to 6;
    rx_buf: byte_string(0 to rx_buffer_size_c - 1);
    rx_count: natural range 0 to rx_buffer_size_c;
    rx_crc: crc_state_t;
    rx_is_data: boolean;
    received_pid: byte;

    -- Identity registers written by SAVE.
    ident: identity_regs_t;
    control_offset: natural range 0 to control_length_max_c;
    control_left: natural range 0 to control_length_max_c;

    -- Outgoing report frame.
    frame: byte_string(0 to report_length_max_c - 1);
    frame_len: natural range 0 to report_length_max_c;
    frame_index: natural range 0 to report_length_max_c - 1;

    wd: unsigned(wd_width_c - 1 downto 0);
    error: std_ulogic;
    packet: std_ulogic;
  end record;

  signal r, rin: regs_t;

  -- Bit 1 is D+, bit 0 is D-.
  signal sampled_s: std_ulogic_vector(1 downto 0);
  signal bus_raw_s: std_ulogic_vector(1 downto 0);

  -- NRZI: an unchanged line level carries a one.
  function nrzi_decode(cur, prev: std_ulogic) return std_ulogic
  is
  begin
    if cur = prev then
      return '1';
    else
      return '0';
    end if;
  end function;

begin

  bus_raw_s <= bus_i.dp & bus_i.dm;

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 2
      )
    port map(
      clock_i => clock_i,
      data_i => bus_raw_s,
      data_o => sampled_s
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.pc <= (others => '0');
      r.link <= (others => '0');
      r.inst <= (others => '0');
      r.inst_ready <= '0';
      r.w <= (others => '0');
      r.c <= '0';
      r.nak <= '1';
      r.err <= '0';
      r.full_speed <= '0';
      r.frame_no <= (others => '0');
      r.t <= (others => '0');
      r.ms_count <= 0;
      r.dp <= '0';
      -- Idle J, so that the first NRZI transition of a packet yields a K.
      r.dm <= '1';
      r.oe <= '0';
      r.dm_prev <= '1';
      r.tx_data <= (others => '0');
      r.tx_index <= 0;
      r.tx_nrzi <= false;
      r.tx_active <= '0';
      r.tx_ones <= 0;
      r.rx_prev <= '1';
      r.rx_shift <= (others => '0');
      r.rx_bit <= 0;
      r.rx_index <= 0;
      r.rx_ones <= 0;
      r.rx_buf <= (others => (others => '0'));
      r.rx_count <= 0;
      r.rx_crc <= crc_init(data_crc_params_c);
      r.rx_is_data <= false;
      r.received_pid <= x"00";
      r.ident <= (others => (others => '0'));
      r.ident(save_reg_ep0_mps_c) <= x"08";
      r.control_offset <= 0;
      r.control_left <= 0;
      r.frame <= (others => (others => '0'));
      r.frame_len <= 0;
      r.frame_index <= 0;
      r.wd <= (others => '0');
      r.error <= '0';
      r.packet <= '0';
    end if;
  end process;

  transition: process(r, sampled_s, report_i) is
    variable op: std_ulogic_vector(4 downto 0);
    variable operand: unsigned(pc_width_c - 1 downto 0);
    variable rx_data: std_ulogic;
    variable rx_byte: byte;
    variable line: std_ulogic_vector(1 downto 0);
    variable bit_last, sample_at: unsigned(t_width_c - 1 downto 0);
    variable sof_crc: std_ulogic_vector(4 downto 0);
    variable save_index: integer;
    variable payload_count: natural range 0 to control_length_max_c;
  begin
    rin <= r;

    op := r.inst(15 downto 11);
    operand := unsigned(r.inst(10 downto 0));
    -- The bus as this machine wants to see it.  Below here nothing
    -- knows about full speed: the lines are swapped on the way in, so
    -- a full-speed bus reads as a low-speed one of the same shape.
    if full_speed_c and r.full_speed = '1' then
      line := sampled_s(0) & sampled_s(1);
      bit_last := to_unsigned(fs_bit_cycles_c - 1, bit_last'length);
      sample_at := to_unsigned(fs_bit_cycles_c / 2, sample_at'length);
    else
      line := sampled_s;
      bit_last := to_unsigned(ls_bit_cycles_c - 1, bit_last'length);
      sample_at := to_unsigned(ls_bit_cycles_c / 2, sample_at'length);
    end if;

    save_index := to_integer(operand(5 downto 0)) - r.control_offset;
    if r.rx_count >= 2 then
      payload_count := r.rx_count - 2;
    else
      payload_count := 0;
    end if;

    -- CRC5 over the frame number, for whichever start-of-frame token
    -- goes out next.  Eleven bits of exclusive or.
    sof_crc := crc_spill_vector(token_crc_params_c,
                                crc_update(token_crc_params_c,
                                           crc_init(token_crc_params_c),
                                           std_ulogic_vector(r.frame_no)));

    rx_data := nrzi_decode(line(0), r.rx_prev);
    rx_byte := rx_data & r.rx_shift(7 downto 1);

    rin.error <= '0';
    rin.packet <= '0';

    if r.ms_count = ms_last_c then
      rin.ms_count <= 0;
    else
      rin.ms_count <= r.ms_count + 1;
    end if;

    rin.wd <= r.wd + 1;

    -- While the driver is off, any line transition realigns the bit
    -- timer so that the sample point lands mid-bit.
    if r.oe = '0' and line(0) /= r.dm_prev then
      rin.t <= to_unsigned(1, r.t'length);
    elsif r.t = bit_last then
      rin.t <= (others => '0');
    else
      rin.t <= r.t + 1;
    end if;
    rin.dm_prev <= line(0);

    if to_integer(r.pc) < rom_c'length then
      rin.inst <= rom_c(to_integer(r.pc));
    else
      rin.inst <= (others => '0');
    end if;

    if r.frame_len /= 0 and is_ready(report_cfg_c, report_i) then
      if r.frame_index + 1 = r.frame_len then
        rin.frame_len <= 0;
        rin.frame_index <= 0;
      else
        rin.frame_index <= r.frame_index + 1;
      end if;
    end if;

    -- Serializer, one symbol per bit time.  A stuffed zero after six
    -- consecutive ones does not consume a data bit, so the byte takes
    -- nine bit times in that case.
    if r.tx_active = '1' and r.t = 0 then
      rin.oe <= '1';

      if r.tx_nrzi then
        if r.tx_ones = 6 then
          rin.dp <= not r.dp;
          rin.dm <= r.dp;
          rin.tx_ones <= 0;
        else
          if r.tx_data(7 - r.tx_index) = '1' then
            rin.dp <= r.dp;
            rin.dm <= not r.dp;
            rin.tx_ones <= r.tx_ones + 1;
          else
            rin.dp <= not r.dp;
            rin.dm <= r.dp;
            rin.tx_ones <= 0;
          end if;

          if r.tx_index = 0 then
            rin.tx_active <= '0';
          else
            rin.tx_index <= r.tx_index - 1;
          end if;
        end if;
      elsif r.tx_ones = 6 then
        -- Stuffing also applies at the end of the CRC, before EOP.
        rin.dp <= not r.dp;
        rin.dm <= r.dp;
        rin.tx_ones <= 0;
      else
        rin.dp <= r.tx_data(4 + r.tx_index);
        rin.dm <= r.tx_data(r.tx_index);
        rin.tx_ones <= 0;

        if r.tx_index = 0 then
          rin.tx_active <= '0';
        else
          rin.tx_index <= r.tx_index - 1;
        end if;
      end if;
    end if;

    -- Instruction stream, held while the serializer owns the bus.
    if r.inst_ready = '0' then
      rin.inst_ready <= '1';
    elsif r.tx_active = '0' then
      rin.pc <= r.pc + 1;
      rin.inst_ready <= '0';

      if op = op_ldi_c then
        rin.w <= operand;

      elsif op = op_start_c then
        -- A packet starts from idle J, which is the NRZI reference the
        -- first SYNC bit is decoded against.
        rin.rx_prev <= '1';
        rin.rx_shift <= (others => '0');
        rin.rx_bit <= 0;
        rin.rx_index <= 0;
        rin.rx_ones <= 0;
        rin.rx_count <= 0;
        rin.rx_crc <= crc_init(data_crc_params_c);
        rin.rx_is_data <= false;
        rin.err <= '0';
        rin.nak <= '1';

        -- Silence consumes the receive budget too; it leaves NAK set.
        if line(0) = '1' then
          if r.t = 0 and r.w = 0 then
            -- Fall through, and leave the receive that follows enough
            -- to finish on immediately.
            rin.w <= to_unsigned(1, r.w'length);
          else
            if r.t = 0 then
              rin.w <= r.w - 1;
            end if;
            rin.pc <= r.pc;
            rin.inst_ready <= '1';
          end if;
        else
          rin.t <= to_unsigned(1, r.t'length);
        end if;

      elsif op = op_out4_c then
        rin.tx_data <= std_ulogic_vector(operand(7 downto 0));
        rin.tx_index <= 3;
        rin.tx_nrzi <= false;
        rin.tx_active <= '1';

      elsif op = op_out0_c then
        if r.t /= 0 then
          rin.pc <= r.pc;
          rin.inst_ready <= '1';
        else
          rin.dp <= '0';
          rin.dm <= '0';
          rin.oe <= '1';
        end if;

      elsif op = op_hiz_c then
        if r.t /= 0 then
          rin.pc <= r.pc;
          rin.inst_ready <= '1';
        else
          rin.oe <= '0';
          rin.tx_ones <= 0;
        end if;

      elsif op = op_outb_c then
        rin.tx_data <= std_ulogic_vector(operand(7 downto 0));
        rin.tx_index <= 7;
        rin.tx_nrzi <= true;
        rin.tx_active <= '1';

      elsif op = op_ret_c then
        rin.pc <= r.link;

      elsif op = op_bz_c then
        if line(0) = '0' then
          rin.pc <= operand;
        end if;

      elsif op = op_bc_c then
        if r.c = '1' then
          rin.pc <= operand;
        end if;

      elsif op = op_bnak_c then
        if r.nak = '1' then
          rin.pc <= operand;
        end if;

      elsif op = op_berr_c then
        if r.err = '1' then
          rin.pc <= operand;
        end if;

      elsif op = op_djnz_c then
        rin.w <= r.w - 1;
        if r.w /= 1 then
          rin.pc <= operand;
        end if;

      elsif op = op_toggle_c then
        rin.c <= not r.c;

      elsif op = op_save_c then
        if to_integer(operand(10 downto 6)) <= save_reg_ep0_mps_c
          and save_index >= 0 and save_index < payload_count then
          rin.ident(to_integer(operand(10 downto 6)))
            <= r.rx_buf(save_index);
        end if;

      elsif op = op_control_c then
        rin.control_offset <= 0;
        rin.control_left <= to_integer(operand);

      elsif op = op_bmore_c then
        if payload_count < r.control_left
          and payload_count = to_integer(unsigned(r.ident(save_reg_ep0_mps_c))) then
          rin.control_left <= r.control_left - payload_count;
          rin.control_offset <= r.control_offset + payload_count;
          rin.pc <= operand;
        else
          rin.control_left <= 0;
        end if;

      elsif op = op_in_c then
        if r.t /= sample_at then
          rin.pc <= r.pc;
          rin.inst_ready <= '1';
        else
          rin.w <= r.w - 1;

          -- Single-ended zero ends the packet.  A data packet checks
          -- out when the running CRC16 over everything that followed
          -- the PID, its two check bytes included, hits the residue.
          if line = "00" then
            if r.rx_bit /= 0 or r.rx_ones = 6 or r.rx_index /= 2 then
              rin.err <= '1';
            end if;
            if r.rx_is_data then
              if r.rx_count >= 2
                and r.err = '0'
                and r.rx_bit = 0 and r.rx_ones /= 6
                and crc_is_valid(data_crc_params_c, r.rx_crc) then
                rin.wd <= (others => '0');
                -- A report, and only a report: the buffer is sized
                -- for control transfers now, and a packet longer than
                -- a report is not one.
                if r.c = '1' and r.rx_count > 2 and r.frame_len = 0
                  and r.rx_count - 2 <= report_length_max_c then
                  rin.frame <= r.rx_buf(0 to report_length_max_c - 1);
                  rin.frame_len <= r.rx_count - 2;
                  rin.frame_index <= 0;
                end if;
              else
                rin.err <= '1';
              end if;
            end if;
          else
            rin.rx_prev <= line(0);

            -- Sixth consecutive one: the symbol on the wire is a
            -- stuffed bit and carries no data.
            if r.rx_ones = 6 then
              rin.rx_ones <= 0;
              if rx_data /= '0' then
                rin.err <= '1';
              end if;
            else
              rin.rx_shift <= rx_byte;

              if rx_data = '1' then
                rin.rx_ones <= r.rx_ones + 1;
              else
                rin.rx_ones <= 0;
              end if;

              if r.rx_bit /= 7 then
                rin.rx_bit <= r.rx_bit + 1;
              else
                rin.rx_bit <= 0;
                if r.rx_index < 2 then
                  rin.rx_index <= r.rx_index + 1;
                end if;

                if r.rx_index = 0 then
                  if rx_byte /= x"80" then
                    rin.err <= '1';
                  end if;
                elsif r.rx_index = 1 then
                  if pid_byte_is_correct(rx_byte) then
                    rin.received_pid <= rx_byte;
                    rin.packet <= '1';
                    if pid_get(rx_byte) /= PID_NAK
                      and pid_get(rx_byte) /= PID_STALL then
                      rin.nak <= '0';
                    end if;
                    if pid_get(rx_byte) = PID_DATA0
                      or pid_get(rx_byte) = PID_DATA1 then
                      rin.rx_is_data <= true;
                    end if;
                  else
                    rin.err <= '1';
                  end if;
                elsif r.rx_index = 2 then
                  rin.rx_crc <= crc_update(data_crc_params_c, r.rx_crc, rx_byte);
                  if r.rx_count < rx_buffer_size_c then
                    rin.rx_buf(r.rx_count) <= rx_byte;
                    rin.rx_count <= r.rx_count + 1;
                  else
                    rin.err <= '1';
                  end if;
                end if;
              end if;
            end if;

            if r.w /= 1 then
              rin.pc <= r.pc;
              rin.inst_ready <= '1';
            else
              rin.err <= '1';
            end if;
          end if;
        end if;

      elsif op = op_wait_c then
        if r.c = '1' then
          rin.wd <= (others => '0');
        end if;
        if r.ms_count /= ms_last_c then
          rin.pc <= r.pc;
          rin.inst_ready <= '1';
        end if;

      elsif op = op_jmp_c then
        rin.pc <= operand;

      elsif op = op_call_c then
        rin.link <= r.pc + 1;
        rin.pc <= operand;

      elsif op = op_speed_c then
        rin.wd <= (others => '0');
        -- Read from the bus as it is rather than as this machine has
        -- been looking at it: which line is pulled up is the thing
        -- being decided, so it cannot already be known.  Built
        -- without full speed, every device reads as a low-speed one
        -- and a full-speed device therefore reads as no device.
        if full_speed_c then
          rin.full_speed <= sampled_s(1);
        end if;
        rin.frame_no <= (others => '0');

      elsif op = op_bfs_c then
        if full_speed_c and r.full_speed = '1' then
          rin.pc <= operand;
        end if;

      elsif op = op_sof_c then
        if operand(0) = '0' then
          rin.tx_data <= std_ulogic_vector(r.frame_no(7 downto 0));
        else
          rin.tx_data <= sof_crc & std_ulogic_vector(r.frame_no(10 downto 8));
          rin.frame_no <= r.frame_no + 1;
        end if;
        rin.tx_index <= 7;
        rin.tx_nrzi <= true;
        rin.tx_active <= '1';
      end if;
    end if;

    -- Enumeration must make progress: silence, NAKs and bad packets
    -- cannot postpone recovery indefinitely. Idle speed sensing and
    -- normal interrupt-poll waits keep a healthy host out of recovery.
    if r.wd = wd_last_c then
      rin.wd <= (others => '0');
      rin.pc <= (others => '0');
      rin.inst_ready <= '0';
      rin.tx_active <= '0';
      rin.tx_ones <= 0;
      rin.oe <= '0';
      rin.error <= '1';
      rin.c <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    if full_speed_c and r.full_speed = '1' then
      bus_o.dp <= r.dm;
      bus_o.dm <= r.dp;
    else
      bus_o.dp <= r.dp;
      bus_o.dm <= r.dm;
    end if;
    bus_o.oe <= r.oe;
    bus_o.dp_pullup_en <= '0';

    identity_o.vid <= unsigned(r.ident(save_reg_vid_h_c))
                      & unsigned(r.ident(save_reg_vid_l_c));
    identity_o.pid <= unsigned(r.ident(save_reg_pid_h_c))
                      & unsigned(r.ident(save_reg_pid_l_c));
    identity_o.if_class <= r.ident(save_reg_if_class_c);
    identity_o.if_subclass <= r.ident(save_reg_if_subclass_c);
    identity_o.if_protocol <= r.ident(save_reg_if_protocol_c);
    identity_o.valid <= r.c = '1';

    status_o.enumerated <= r.c = '1';
    status_o.error <= r.error;
    status_o.packet <= r.packet;
    status_o.program_counter <= resize(r.pc, status_o.program_counter'length);
    status_o.full_speed <= r.full_speed = '1';
    status_o.received_pid <= r.received_pid;
    status_o.control_debug <= r.ident(save_reg_ep0_mps_c)
      & std_ulogic_vector(to_unsigned(r.control_left, 8))
      & std_ulogic_vector(to_unsigned(r.control_offset, 8))
      & r.err & std_ulogic_vector(to_unsigned(r.rx_count, 7));

    if r.frame_len /= 0 then
      report_o <= transfer(report_cfg_c,
                           bytes => (0 => r.frame(r.frame_index)),
                           valid => true,
                           last => r.frame_index + 1 = r.frame_len);
    else
      report_o <= transfer(report_cfg_c,
                           bytes => (0 => x"00"),
                           valid => false);
    end if;
  end process;

end architecture;
