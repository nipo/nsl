library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_data.bytestream.all;
use nsl_amba.dma_request.all;

-- Microcoded memory-to-memory DMA controller on an AXI4 master.
--
-- Channel threads execute programs fetched from memory, whose
-- instruction set is compatible with the channel thread instructions
-- of ARM's CoreLink DMA-330 (as its Technical Reference Manual,
-- ARM DDI 0424D, describes it).  Compatibility is partial, see
-- index.rst in this directory for the exact coverage and deviations.
package axi_m2m_dma is

  constant max_channel_count_c : natural := 8;
  constant max_event_count_c : natural := 32;
  constant max_peripheral_count_c : natural := 32;

  -- Channel status, as the DMA-330 CSR register encodes it.  Only
  -- stopped, executing, waiting for event, at barrier, waiting for
  -- peripheral, killing, completing, faulting completing and faulting
  -- are ever reported.
  subtype channel_state_t is std_ulogic_vector(3 downto 0);
  constant channel_stopped_c : channel_state_t := "0000";
  constant channel_executing_c : channel_state_t := "0001";
  constant channel_cache_miss_c : channel_state_t := "0010";
  constant channel_updating_pc_c : channel_state_t := "0011";
  constant channel_waiting_event_c : channel_state_t := "0100";
  constant channel_at_barrier_c : channel_state_t := "0101";
  constant channel_waiting_peripheral_c : channel_state_t := "0111";
  constant channel_killing_c : channel_state_t := "1000";
  constant channel_completing_c : channel_state_t := "1001";
  constant channel_faulting_completing_c : channel_state_t := "1110";
  constant channel_faulting_c : channel_state_t := "1111";

  -- Channel fault type, bit layout of the DMA-330 FTR register.  Bits
  -- that are never set: ch_evnt_err, ch_periph_err, ch_rdwr_err
  -- (no security extension), lockup_err.  FTRD, the manager's, uses
  -- undef_instr, operand_invalid, instr_fetch_err and dbg_instr at the
  -- same positions.
  subtype fault_t is std_ulogic_vector(31 downto 0);
  constant fault_undef_instr_c : natural := 0;
  constant fault_operand_invalid_c : natural := 1;
  constant fault_ch_evnt_err_c : natural := 5;
  constant fault_ch_periph_err_c : natural := 6;
  constant fault_ch_rdwr_err_c : natural := 7;
  constant fault_mfifo_err_c : natural := 12;
  constant fault_st_data_unavailable_c : natural := 13;
  constant fault_instr_fetch_err_c : natural := 16;
  constant fault_data_write_err_c : natural := 17;
  constant fault_data_read_err_c : natural := 18;
  constant fault_dbg_instr_c : natural := 30;
  constant fault_lockup_err_c : natural := 31;

  -- Identification, as the conceptual 32-bit peripheral and component
  -- ID registers of the DMA-330 APB register file hold them (bytes at
  -- offsets 0xfe0 to 0xffc).  The peripheral ID keeps the layout
  -- (integration_cfg [24], revision [23:20], designer [19:12],
  -- part_number [11:0]) with values of this implementation: no JEP106
  -- designer, part number 0x0da, revision 0.  The component ID is the
  -- PrimeCell/CoreSight preamble with the generic IP component class.
  constant periph_id_c : unsigned(31 downto 0) := x"000000da";
  constant pcell_id_c : unsigned(31 downto 0) := x"b105f00d";

  -- APB register offsets, the DMA-330's.  Channel n's FTR is at
  -- reg_ftr0_c + 4 n, its CSR and CPC at reg_csr0_c + 8 n and
  -- reg_cpc0_c + 8 n, its SAR, DAR, CCR, LC0 and LC1 at reg_sar0_c,
  -- reg_dar0_c, reg_ccr0_c, reg_lc0_0_c and reg_lc1_0_c + 32 n.
  constant reg_dsr_c : natural := 16#000#;
  constant reg_dpc_c : natural := 16#004#;
  constant reg_inten_c : natural := 16#020#;
  constant reg_int_event_ris_c : natural := 16#024#;
  constant reg_intmis_c : natural := 16#028#;
  constant reg_intclr_c : natural := 16#02c#;
  constant reg_fsrd_c : natural := 16#030#;
  constant reg_fsrc_c : natural := 16#034#;
  constant reg_ftrd_c : natural := 16#038#;
  constant reg_ftr0_c : natural := 16#040#;
  constant reg_csr0_c : natural := 16#100#;
  constant reg_cpc0_c : natural := 16#104#;
  constant reg_sar0_c : natural := 16#400#;
  constant reg_dar0_c : natural := 16#404#;
  constant reg_ccr0_c : natural := 16#408#;
  constant reg_lc0_0_c : natural := 16#40c#;
  constant reg_lc1_0_c : natural := 16#410#;
  constant reg_dbgstatus_c : natural := 16#d00#;
  constant reg_dbgcmd_c : natural := 16#d04#;
  constant reg_dbginst0_c : natural := 16#d08#;
  constant reg_dbginst1_c : natural := 16#d0c#;
  constant reg_cr0_c : natural := 16#e00#;
  constant reg_cr1_c : natural := 16#e04#;
  constant reg_cr2_c : natural := 16#e08#;
  constant reg_cr3_c : natural := 16#e0c#;
  constant reg_cr4_c : natural := 16#e10#;
  constant reg_crd_c : natural := 16#e14#;
  constant reg_wd_c : natural := 16#e80#;
  constant reg_periph_id0_c : natural := 16#fe0#;
  constant reg_pcell_id0_c : natural := 16#ff0#;

  -- Microcoded memory-to-memory DMA controller.
  --
  -- Threads
  -- -------
  --
  -- A manager thread and channel_count_c channel threads share one
  -- instruction execution unit, one instruction at a time: the manager,
  -- when it can run, between two channel instructions, the channels
  -- round-robin.  Channel contexts live in a memory (LUT RAM or block
  -- RAM), 8 words a channel, not in registers.  Every channel has its
  -- own SAR, DAR, CCR, LC0, LC1 and PC registers, and runs the channel
  -- thread instruction set of the DMA-330:
  -- DMAADDH, DMAADNH, DMAEND, DMAFLUSHP, DMAKILL, DMALD[S|B],
  -- DMALDP<S|B>, DMALP, DMALPEND[S|B] (both loop counters and
  -- forever form), DMAMOV (SAR, CCR, DAR), DMANOP, DMARMB, DMASEV,
  -- DMAST[S|B], DMASTP<S|B>, DMASTZ, DMAWFE, DMAWFP (single, burst,
  -- periph), DMAWMB.  The manager runs DMAEND, DMAGO, DMAKILL, DMANOP,
  -- DMASEV and DMAWFE.
  --
  -- Any other opcode and an instruction of the other thread kind fault
  -- the thread with undef_instr.  Reserved operand bits are ignored,
  -- but a DMAMOV to a register other than SAR, CCR and DAR, or a DMAGO
  -- with reserved bits set, faults with operand_invalid.  So does an
  -- event, peripheral or channel number beyond the configured count, a
  -- DMAMOV CCR setting a burst size wider than the AXI data bus or a
  -- reserved endian swap size, a non-zero one without endian_swap_c or
  -- one larger than both burst sizes, and a fixed-address transfer
  -- whose address is not aligned to its burst size.  Faults leave the
  -- thread faulting until it is killed.  CCR bit 31 is not stored.
  --
  -- A thread's PC (CPC, DPC) is past a waiting instruction (DMAWFE,
  -- DMAWFP, DMARMB, DMAWMB, or the discontinuity below) as soon as it
  -- executes, past DMAEND and DMAKILL, on an instruction that faulted
  -- precisely.
  --
  -- With boot_from_pc_c, the manager starts executing at boot_addr_c
  -- when reset is released, as the DMA-330's with its boot_from_pc
  -- tie-off; otherwise it is stopped.  Either way, the host starts
  -- channels and kills threads through the debug registers.
  --
  -- Instructions are fetched with single-beat reads of one data bus
  -- word, one fetch per instruction word crossed, no cache.
  --
  -- Registers
  -- ---------
  --
  -- apb_i/apb_o is the DMA-330 register file (see reg_*_c): status,
  -- interrupts, faults, channel registers, debug instruction registers,
  -- configuration and identification.  There is no TrustZone: this is
  -- the secure interface, every thread, event and peripheral is secure,
  -- DMAGO's ns operand is ignored.  apb_config_c must have 32-bit data
  -- and at least 12 bits of address; the register file decodes the low
  -- 12 bits.  Register accesses complete in a bounded number of cycles,
  -- independent of the thread engine: the controller may reach its own
  -- registers through its AXI master (a program loading channel
  -- registers or writing DBGINST0/1 and DBGCMD), including through an
  -- interconnect it shares with the host.  Channel registers read in
  -- three cycles, from a copy of the context memory, as the last
  -- instruction write-back left them: at most one instruction stale,
  -- two of them read one after the other may straddle a write-back.
  -- Other reads and all writes complete without wait states.  A DBGCMD
  -- written while DBGSTATUS is busy is queued, one deep: with one
  -- already queued, it is ignored.  Reserved offsets read as zero and
  -- ignore writes.
  --
  -- Data
  -- ----
  --
  -- DMALD reads into the channel's MFIFO, DMAST writes out of it.  The
  -- MFIFO holds bytes, as the DMA-330's does: a load appends the bytes
  -- its AXI burst transfers, a store takes as many as its own burst
  -- transfers, whatever the address alignments, burst sizes and
  -- lengths of either side.  A burst transfers len * size bytes, minus
  -- the offset of an incrementing burst's address in its first beat.
  -- Bursts that would cross a 4 kB boundary are split in two, as the
  -- DMA-330 does.
  --
  -- Each channel owns 2**mfifo_depth_l2_c data bus words of MFIFO.
  -- A DMALD waits for room in its channel's MFIFO, and faults with
  -- mfifo_err when room can never come.  A DMAST whose data no
  -- previous DMALD provides faults with st_data_unavailable.  A store
  -- burst only starts once all its data is in the MFIFO.
  --
  -- A DMAMOV changing the destination byte lane alignment (DAR modulo
  -- the bus width), the endian swap size, the destination increment
  -- or, fixed, the destination burst size is a discontinuity, as the
  -- DMA-330 defines it: the channel waits for its transfers to
  -- complete, then drops the data left in its MFIFO.
  --
  -- With endian_swap_c, a store swaps the bytes within each group of
  -- 2**endian_swap_size bytes it writes, a group spanning several
  -- beats when the swap size exceeds the destination burst size.  DAR and the store's length
  -- must be multiples of the group size, as the DMA-330 requires, or
  -- the stored data is unpredictable.
  --
  -- At most one read burst and one write burst are in flight on the
  -- AXI master.  AXI ID is the channel number, the channel count for
  -- the manager's instruction fetches.  AXI protection and cache
  -- attributes come from CCR, instruction fetches are privileged,
  -- secure, instruction accesses.  An error response on a data read or
  -- write does not stop the channel: SAR and DAR advance, peripherals
  -- are acknowledged, a failed load's bytes enter the MFIFO with
  -- whatever data the bus returned and stores write them.  With
  -- failed_store_fault_c, the first store that would take bytes a
  -- failed load brought faults instead, past itself, with
  -- data_read_err: nothing reaches the bus, DAR stays, a DMASTP
  -- acknowledges nothing, as the Zynq-7000's DMA-330 does once the
  -- error is known; a store whose data is not loaded yet then waits for
  -- the channel's loads (CSR at barrier) so that it is known when it
  -- executes.  This costs a few hundred LUTs and some throughput for
  -- something a program should not do, hence off by default.  The
  -- channel faults with
  -- data_read_err or data_write_err once it waits for its transfers:
  -- at DMAEND, at a barrier of the failed direction or at a
  -- discontinuity, its PC past that instruction.  An error on an
  -- instruction fetch faults with instr_fetch_err.
  --
  -- Events
  -- ------
  --
  -- Event-interrupt resource n has one raw status bit (INT_EVENT_RIS).
  -- DMASEV n sets it if INTEN bit n is set (an interrupt), else wakes
  -- every thread waiting in DMAWFE n, or, if none waits, sets it (a
  -- pending event).  irq_o(n) is the bit masked by INTEN (INTMIS): a
  -- pending event becomes an interrupt when INTEN enables it.  An
  -- INTCLR write with bit n set clears it while INTEN bit n is set; a
  -- DMAWFE n takes it while INTEN bit n is clear.
  --
  -- irq_abort_o is set while a thread is faulting.
  --
  -- Peripherals
  -- -----------
  --
  -- periph_i/periph_o are peripheral_count_c peripheral request
  -- interfaces, each with a request FIFO of request_depth_c entries
  -- (the DMA-330's request acceptance capability; the Zynq-7000's
  -- takes at least 3).  DMAWFP pops
  -- requests as the DMA-330 does, DMALDP and DMASTP acknowledge the
  -- completion of their transfer.  DMAFLUSHP discards the
  -- peripheral's pending request, sends a flush request and discards
  -- incoming requests until the peripheral acknowledges the flush.  It
  -- does not wait for the channel's transfers: the flush request can
  -- overtake the acknowledge of a DMALDP or DMASTP still in flight,
  -- a barrier before DMAFLUSHP orders them.
  --
  -- Configuration
  -- -------------
  --
  -- config_c is the AXI4 master configuration.  It must have 32-bit
  -- addresses, a data bus of 32 to 128 bits, bursts, size and length of
  -- at least 16 beats.  With id_width non-zero, ID carries the thread
  -- number, it must then count up to channel_count_c.
  component axi_m2m_microcoded_dma is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      apb_config_c : nsl_amba.apb.config_t;
      channel_count_c : positive range 1 to max_channel_count_c := 1;
      event_count_c : positive range 1 to max_event_count_c := 1;
      peripheral_count_c : positive range 1 to max_peripheral_count_c := 1;
      request_depth_c : positive range 1 to 8 := 1;
      mfifo_depth_l2_c : positive := 4;
      endian_swap_c : boolean := false;
      failed_store_fault_c : boolean := false;
      boot_from_pc_c : boolean := false;
      boot_addr_c : unsigned(31 downto 0) := x"00000000"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t;

      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t;

      irq_o : out std_ulogic_vector(event_count_c-1 downto 0);
      irq_abort_o : out std_ulogic;

      periph_i : in peripheral_vector(0 to peripheral_count_c-1) := (others => peripheral_idle_c);
      periph_o : out dmac_vector(0 to peripheral_count_c-1)
      );
  end component;

  -- Program assembly helpers
  -- ------------------------
  --
  -- Each function returns the encoding of one instruction as a byte
  -- string in memory order, ready to be concatenated into a program.

  -- Loop counter selection for asm_lp/asm_lpend
  subtype loop_counter_t is natural range 0 to 1;

  -- Condition suffix of DMALD, DMAST, DMALPEND: none, S or B.
  type condition_t is (
    COND_ALWAYS,
    COND_SINGLE,
    COND_BURST
    );

  -- DMAWFP operand
  type wfp_mode_t is (
    WFP_SINGLE,
    WFP_BURST,
    WFP_PERIPH
    );

  -- DMAADDH / DMAADNH / DMAMOV address register
  type address_register_t is (
    REG_SAR,
    REG_DAR
    );

  -- CCR value.  size_l2 is log2 of bytes per beat, len the beat count
  -- (1 to 16), incr selects incrementing (rather than fixed) bursts.
  function ccr_value(src_size_l2 : natural range 0 to 4 := 0;
                     src_len : positive range 1 to 16 := 1;
                     src_incr : boolean := true;
                     src_prot : natural range 0 to 7 := 0;
                     src_cache : natural range 0 to 7 := 0;
                     dst_size_l2 : natural range 0 to 4 := 0;
                     dst_len : positive range 1 to 16 := 1;
                     dst_incr : boolean := true;
                     dst_prot : natural range 0 to 7 := 0;
                     dst_cache : natural range 0 to 7 := 0;
                     swap_size_l2 : natural range 0 to 7 := 0) return unsigned;

  function asm_end return byte_string;
  function asm_kill return byte_string;
  function asm_nop return byte_string;
  function asm_rmb return byte_string;
  function asm_wmb return byte_string;
  function asm_mov_sar(value : unsigned) return byte_string;
  function asm_mov_dar(value : unsigned) return byte_string;
  function asm_mov_ccr(value : unsigned) return byte_string;
  -- DMAMOV with raw rd field, for encoding invalid registers
  function asm_mov(rd : natural range 0 to 7; value : unsigned) return byte_string;
  function asm_addh(reg : address_register_t; value : natural range 0 to 65535) return byte_string;
  -- value is the 16-bit immediate as encoded, one-extended at execution
  function asm_adnh(reg : address_register_t; value : natural range 0 to 65535) return byte_string;
  function asm_ld(cond : condition_t := COND_ALWAYS) return byte_string;
  function asm_st(cond : condition_t := COND_ALWAYS) return byte_string;
  function asm_stz return byte_string;
  -- cond must be COND_SINGLE or COND_BURST
  function asm_ldp(cond : condition_t; periph : natural range 0 to 31) return byte_string;
  function asm_stp(cond : condition_t; periph : natural range 0 to 31) return byte_string;
  -- iterations is the actual loop count, 1 to 256
  function asm_lp(lc : loop_counter_t; iterations : positive range 1 to 256) return byte_string;
  -- jump is the distance in bytes from the first instruction of the
  -- loop body to the DMALPEND, i.e. the length of the loop body.
  function asm_lpend(lc : loop_counter_t; jump : natural range 0 to 255;
                     cond : condition_t := COND_ALWAYS) return byte_string;
  -- DMALPEND closing a DMALPFE loop, exits when request_last is set.
  function asm_lpend_forever(jump : natural range 0 to 255) return byte_string;
  function asm_wfp(periph : natural range 0 to 31; mode : wfp_mode_t) return byte_string;
  function asm_flushp(periph : natural range 0 to 31) return byte_string;
  function asm_sev(event : natural range 0 to 31) return byte_string;
  function asm_wfe(event : natural range 0 to 31; invalid : boolean := false) return byte_string;
  -- Manager thread only
  function asm_go(channel : natural range 0 to 7; pc : unsigned; ns : boolean := false) return byte_string;

end package;

package body axi_m2m_dma is

  function to_byte_s(v : natural) return byte is
  begin
    return byte(to_unsigned(v mod 256, 8));
  end function;

  function bs2(a, b : natural) return byte_string is
    variable ret : byte_string(0 to 1);
  begin
    ret(0) := to_byte_s(a);
    ret(1) := to_byte_s(b);
    return ret;
  end function;

  function bs3(a, b, c : natural) return byte_string is
    variable ret : byte_string(0 to 2);
  begin
    ret(0) := to_byte_s(a);
    ret(1) := to_byte_s(b);
    ret(2) := to_byte_s(c);
    return ret;
  end function;

  function le32(value : unsigned) return byte_string
  is
    variable v : unsigned(31 downto 0) := resize(value, 32);
    variable ret : byte_string(0 to 3);
  begin
    for i in ret'range
    loop
      ret(i) := std_ulogic_vector(v(8*i+7 downto 8*i));
    end loop;
    return ret;
  end function;

  function cond_bits(cond : condition_t) return natural is
  begin
    case cond is
      when COND_ALWAYS => return 0;
      when COND_SINGLE => return 1;
      when COND_BURST => return 3;
    end case;
  end function;

  function ccr_value(src_size_l2 : natural range 0 to 4 := 0;
                     src_len : positive range 1 to 16 := 1;
                     src_incr : boolean := true;
                     src_prot : natural range 0 to 7 := 0;
                     src_cache : natural range 0 to 7 := 0;
                     dst_size_l2 : natural range 0 to 4 := 0;
                     dst_len : positive range 1 to 16 := 1;
                     dst_incr : boolean := true;
                     dst_prot : natural range 0 to 7 := 0;
                     dst_cache : natural range 0 to 7 := 0;
                     swap_size_l2 : natural range 0 to 7 := 0) return unsigned
  is
    variable ret : unsigned(31 downto 0) := (others => '0');
  begin
    if src_incr then
      ret(0) := '1';
    end if;
    ret(3 downto 1) := to_unsigned(src_size_l2, 3);
    ret(7 downto 4) := to_unsigned(src_len - 1, 4);
    ret(10 downto 8) := to_unsigned(src_prot, 3);
    ret(13 downto 11) := to_unsigned(src_cache, 3);
    if dst_incr then
      ret(14) := '1';
    end if;
    ret(17 downto 15) := to_unsigned(dst_size_l2, 3);
    ret(21 downto 18) := to_unsigned(dst_len - 1, 4);
    ret(24 downto 22) := to_unsigned(dst_prot, 3);
    ret(27 downto 25) := to_unsigned(dst_cache, 3);
    ret(30 downto 28) := to_unsigned(swap_size_l2, 3);
    return ret;
  end function;

  function asm_end return byte_string is
  begin
    return from_hex("00");
  end function;

  function asm_kill return byte_string is
  begin
    return from_hex("01");
  end function;

  function asm_nop return byte_string is
  begin
    return from_hex("18");
  end function;

  function asm_rmb return byte_string is
  begin
    return from_hex("12");
  end function;

  function asm_wmb return byte_string is
  begin
    return from_hex("13");
  end function;

  function asm_mov(rd : natural range 0 to 7; value : unsigned) return byte_string is
  begin
    return bs2(16#bc#, rd) & le32(value);
  end function;

  function asm_mov_sar(value : unsigned) return byte_string is
  begin
    return asm_mov(0, value);
  end function;

  function asm_mov_ccr(value : unsigned) return byte_string is
  begin
    return asm_mov(1, value);
  end function;

  function asm_mov_dar(value : unsigned) return byte_string is
  begin
    return asm_mov(2, value);
  end function;

  function ra_bit(reg : address_register_t) return natural is
  begin
    case reg is
      when REG_SAR => return 0;
      when REG_DAR => return 2;
    end case;
  end function;

  function asm_addh(reg : address_register_t; value : natural range 0 to 65535) return byte_string is
  begin
    return bs3(16#54# + ra_bit(reg), value mod 256, value / 256);
  end function;

  function asm_adnh(reg : address_register_t; value : natural range 0 to 65535) return byte_string is
  begin
    return bs3(16#5c# + ra_bit(reg), value mod 256, value / 256);
  end function;

  function asm_ld(cond : condition_t := COND_ALWAYS) return byte_string is
    variable ret : byte_string(0 to 0);
  begin
    ret(0) := to_byte_s(16#04# + cond_bits(cond));
    return ret;
  end function;

  function asm_st(cond : condition_t := COND_ALWAYS) return byte_string is
    variable ret : byte_string(0 to 0);
  begin
    ret(0) := to_byte_s(16#08# + cond_bits(cond));
    return ret;
  end function;

  function asm_stz return byte_string is
  begin
    return from_hex("0c");
  end function;

  function asm_ldp(cond : condition_t; periph : natural range 0 to 31) return byte_string is
  begin
    assert cond /= COND_ALWAYS
      report "DMALDP needs a S or B suffix"
      severity failure;
    return bs2(16#24# + cond_bits(cond), periph * 8);
  end function;

  function asm_stp(cond : condition_t; periph : natural range 0 to 31) return byte_string is
  begin
    assert cond /= COND_ALWAYS
      report "DMASTP needs a S or B suffix"
      severity failure;
    return bs2(16#28# + cond_bits(cond), periph * 8);
  end function;

  function asm_lp(lc : loop_counter_t; iterations : positive range 1 to 256) return byte_string is
  begin
    return bs2(16#20# + 2 * lc, iterations - 1);
  end function;

  function asm_lpend(lc : loop_counter_t; jump : natural range 0 to 255;
                     cond : condition_t := COND_ALWAYS) return byte_string is
  begin
    return bs2(16#38# + 4 * lc + cond_bits(cond), jump);
  end function;

  function asm_lpend_forever(jump : natural range 0 to 255) return byte_string is
  begin
    return bs2(16#2c#, jump);
  end function;

  function asm_wfp(periph : natural range 0 to 31; mode : wfp_mode_t) return byte_string is
  begin
    case mode is
      when WFP_SINGLE => return bs2(16#30#, periph * 8);
      when WFP_PERIPH => return bs2(16#31#, periph * 8);
      when WFP_BURST => return bs2(16#32#, periph * 8);
    end case;
  end function;

  function asm_flushp(periph : natural range 0 to 31) return byte_string is
  begin
    return bs2(16#35#, periph * 8);
  end function;

  function asm_sev(event : natural range 0 to 31) return byte_string is
  begin
    return bs2(16#34#, event * 8);
  end function;

  function asm_wfe(event : natural range 0 to 31; invalid : boolean := false) return byte_string is
  begin
    if invalid then
      return bs2(16#36#, event * 8 + 2);
    else
      return bs2(16#36#, event * 8);
    end if;
  end function;

  function asm_go(channel : natural range 0 to 7; pc : unsigned; ns : boolean := false) return byte_string is
  begin
    if ns then
      return bs2(16#a2#, channel) & le32(pc);
    else
      return bs2(16#a0#, channel) & le32(pc);
    end if;
  end function;

end package body;
