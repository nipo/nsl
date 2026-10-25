=====================================
 Microcoded memory-to-memory DMA
=====================================

:vhdl:component:`axi_m2m_microcoded_dma
<nsl_amba.axi_m2m_dma.axi_m2m_microcoded_dma>` is a DMA controller
on an AXI4 master port, running manager and channel programs fetched
from memory, controlled through an APB register file.  Its instruction
set and register file are compatible with the ones of ARM's CoreLink
DMA-330, as its Technical Reference Manual (ARM DDI 0424D, revision
r1p2) describes them, so that programs assembled for a DMA-330 run
unmodified, and a DMA-330 driver finds the registers it expects,
within the limits below.  Compatibility is partial: the deviations
below list where it stops.

Interfaces
==========

* ``axi_o``/``axi_i``: AXI4 master, 32-bit addresses, 32 to 128-bit
  data, bursts of up to 16 beats with size.  ID carries the channel
  number, the channel count for the manager's instruction fetches, as
  the DMA-330's.

* ``apb_i``/``apb_o``: APB slave, the DMA-330 register file (the secure
  one: there is a single interface).  ``reg_*_c`` constants in the
  package give the offsets.

* ``irq_o``, ``irq_abort_o``: interrupt outputs, ``irq_o`` is INTMIS,
  ``irq_abort_o`` is set while a thread is faulting.

* ``periph_i``/``periph_o``: peripheral request interfaces, with the
  DMA-330 signals (drvalid, drtype, drlast, drready, davalid, datype,
  daready) grouped in :vhdl:type:`peripheral_t
  <nsl_amba.dma_request.peripheral_t>` (peripheral driven) and
  :vhdl:type:`dmac_t <nsl_amba.dma_request.dmac_t>` (controller
  driven) records of :vhdl:package:`nsl_amba.dma_request`, shared with
  the PS7 wrapper's DMAC ports.

Generics are the channel count (1 to 8), event count (1 to 32),
peripheral count (1 to 32), the per-channel MFIFO depth, in bus
words, as a power of two, whether endian swap is supported, and the
DMA-330's boot_from_pc and boot_addr tie-offs.

Architecture
============

One thread engine executes one instruction of one thread at a time.
Channel contexts live in a context memory (``nsl_memory.ram.ram_auto``:
LUT RAM, or block RAM from 8 channels on), eight 32-bit words a
channel: PC, SAR, DAR, CCR, loop counters, MFIFO pointers and a
scheduling word (state, what the channel waits for, request flags and
fault bits).  Registers hold the context of the channel executing an
instruction, and a few flags a channel or an event: event waits,
killing and faulting flags, transfer error latches.

Idle, the engine scans the channels round-robin, one a cycle: it reads
a channel's scheduling word and evaluates its wait against those flags,
the peripheral request heads and the transfers in flight.  A channel
that can proceed is switched in: its context words are read while its
instruction is fetched, the instruction executes, then the words it
changed are written back.  Debug instructions and channel register
reads are served between scans.

The manager thread runs on the same engine, fetch and decode included.
Its context (PC, state, wakeup event, faults, an event wait flag per
event) is in registers rather than in the context memory: a ninth
eight-word context, for two meaningful words, would double the context
memory at two and four channels, it being sized to a power of two.  It
is switched in, when it can run, instead of the next channel scan, once
after each channel instruction or full scan round, which is the
DMA-330's "manager between two channels" arbitration.  Its DMAGO starts
a channel the way a debug DMAGO does.  Only ``boot_from_pc_c`` starts
the manager, debug instructions cannot: without it, the manager's
execution logic is optimized away.

The register file is an APB slave (``nsl_amba.apb.apb_regmap``) holding
INTEN, WD, DBGINST0/1, the debug command handshake and a one-deep
debug command queue.  No register access waits on the thread engine,
which may itself wait on an access to these registers (a channel
loading or storing them through its AXI master, possibly through an
interconnect shared with the host): manager, fault summary and event
registers are engine outputs, read without wait states; channel
registers are read in three cycles from a copy of the context memory,
written along with it (LUT RAM, a block RAM at eight channels), whose
second read port only serves them.

The engine hands load and store transfers to a reader and a writer,
each owning one direction of the AXI port with one burst in flight;
they keep a byte count per channel of what they moved into and out of
the MFIFO, updated as bursts go.  Instructions are fetched through the
reader.

The MFIFO is one byte-wide RAM per data bus byte lane
(``nsl_memory.ram.ram_auto``, LUT RAM when small).  A channel's data
is a byte stream: loads append the bytes their bursts bring, stores
take the bytes their bursts need, whatever the alignments, sizes and
lengths on either side.  Byte ``n`` of the stream lives in lane ``n mod
W``, so realignment is a rotation on the way in and on the way out.

Instruction set coverage
========================

Supported channel instructions: DMAADDH, DMAADNH, DMAEND, DMAFLUSHP,
DMAKILL, DMALD, DMALDS, DMALDB, DMALDPS, DMALDPB, DMALP (both loop
counters), DMALPEND, DMALPENDS, DMALPENDB, DMALPEND closing a DMALPFE
loop, DMAMOV SAR/CCR/DAR, DMANOP, DMARMB, DMASEV, DMAST, DMASTS,
DMASTB, DMASTPS, DMASTPB, DMASTZ, DMAWFE, DMAWFP single/burst/periph,
DMAWMB.

Supported manager instructions: DMAEND, DMAGO, DMAKILL, DMANOP,
DMASEV, DMAWFE.

Any other encoding faults the thread with ``undef_instr``, including
an instruction of the other thread kind, encodings with ``bs`` set and
``x`` clear, and DMALPEND encodings of a DMALPFE loop other than
``0x2c`` (the one the DMA-330 assembler produces).  A DMAMOV to a
register other than SAR, CCR and DAR and a DMAGO with reserved bits
set fault with ``operand_invalid``.  Other reserved operand bits are
ignored, as the Zynq-7000's DMA-330 does.

Faults follow the DMA-330 fault types and states: a channel goes
faulting-completing, completes the transfers of the instructions it
executed before the fault, then stays faulting until killed; the
manager goes faulting at once.  A kill drops the transfers that did
not start.  A precise fault leaves the PC on the faulting instruction.

Registers
=========

All of the DMA-330's: DSR, DPC, INTEN, INT_EVENT_RIS, INTMIS, INTCLR,
FSRD, FSRC, FTRD, FTR0-7, CSR0-7, CPC0-7, SAR, DAR, CCR, LC0, LC1 of
each channel, DBGSTATUS, DBGCMD, DBGINST0/1, CR0-CR4, CRD, WD, and the
peripheral and component identification registers.  Channels beyond
the channel count read as zero.  Configuration registers describe
this implementation: CR1 an instruction "cache" of one line of one bus
word, CRD read and write queues of one entry and one read and one
write in flight, the MFIFO depth of all channels (saturated at 1024
lines).  ``periph_id_c`` and ``pcell_id_c`` are the identification
values.

The host issues DMAGO, DMASEV and DMAKILL through DBGINST0/1 and
DBGCMD, to the manager or to a channel.  DBGSTATUS reads busy from the
DBGCMD write until the instruction executed.  At reset, the manager is
stopped, or, with ``boot_from_pc_c``, executes from ``boot_addr_c``.

Deviations
==========

MFIFO
  Every channel owns a fixed share of the MFIFO instead of sharing one
  pool.  The MFIFO is accounted in bytes rather than in entries packed
  after the destination alignment.  There is no load-lock and no
  watchdog: a DMALD that does not fit waits for queued stores to make
  room, and when none are left to do so, faults with ``mfifo_err``,
  precisely (the DMA-330 would detect a lock-up through its
  watchdog).  A DMALD or DMAST moving more bytes than the channel's
  MFIFO also faults with ``mfifo_err``, precisely.

Source updates
  The DMA-330 waits for outstanding reads when a DMAMOV changes the
  source alignment, increment or burst size.  Here, the MFIFO is a
  byte stream that such updates do not affect: nothing waits.  (A
  destination discontinuity waits and discards as the DMA-330 does.)

Endian swap
  Optional, with the ``endian_swap_c`` generic; without it, a DMAMOV
  CCR with a non-zero ``endian_swap_size`` faults with
  ``operand_invalid``.  With it, a swap size larger than both burst
  sizes faults the same way; the larger bounds it and a swapped group
  may span several destination beats, as on the Zynq-7000's DMA-330.
  The DMA-330 requires SAR, DAR and the store lengths to be aligned to
  the swap size; when they are not, the stored data is unpredictable
  (the Zynq's faults the store for a misaligned source and stores
  other bytes for a misaligned destination).  CCR bit 31 is not
  stored, as on the Zynq's.

Burst size
  A DMAMOV CCR with a source or destination burst size wider than the
  data bus, or reserved, faults with ``operand_invalid``.  The DMA-330
  signals a precise abort without naming a fault type.

Fixed unaligned bursts
  A fixed-address load or store whose address is not aligned to its
  burst size faults with ``operand_invalid``.  The DMA-330 calls it a
  programming error; the Zynq-7000's transfers the lanes from the
  address to the end of the beat.

Store without data
  A DMAST beyond what the loads provided faults precisely with
  ``st_data_unavailable``; the Zynq-7000's issues the store and faults
  imprecisely.  Transfer errors (SLVERR, DECERR) fault as the
  Zynq-7000's do: once the channel waits for its transfers, at DMAEND,
  at a barrier of the failed direction or at a discontinuity.  A store
  of a failed load's bytes writes them, with whatever data the bus
  returned (a deviation).  With ``failed_store_fault_c``, as the
  Zynq-7000's once the error is known, the first store that would take
  them faults instead, past itself, DAR staying, nothing reaching the
  bus, a DMASTP acknowledging nothing; stores of bytes before them are
  issued.  A store whose data is not loaded yet then waits for the
  channel's loads (CSR reads at barrier meanwhile), so the error is
  always known when it executes.  The Zynq-7000's, when a store
  executes before the load's error came back, drops the store and
  faults at DMAEND instead.  The generic is off by default: it costs
  about 90 FFs and 200 LUTs at 8 channels and the store's wait, for
  something a program is not meant to do.

Security
  No TrustZone: the manager, channels, events and peripherals are all
  secure (boot_manager_ns, boot_irq_ns and boot_periph_ns tied low),
  there is one APB interface, the secure one.  DMAGO's ns operand is
  ignored: the channel starts secure, CSR's CNS reads 0.
  ``ch_rdwr_err``, ``ch_periph_err``, ``ch_evnt_err``, ``dmago_err``
  and ``mgr_evnt_err`` never happen, CCR protection bits go to AxPROT
  unchecked.

Instruction fetch
  No instruction cache.  Every instruction is fetched from memory, one
  single-beat, bus-wide read per bus word it spans (AxCACHE 0b0110,
  AxPROT privileged, secure, instruction).  The ``invalid`` operand of
  DMAWFE is accepted and ignored.  Cache miss and updating PC states
  are never reported.

DMAKILL in a channel program
  The DMA-330 forbids it.  Here, it kills the channel.

Peripheral requests
  A request FIFO of ``request_depth_c`` entries per peripheral, one by
  default (the Zynq-7000's takes six).  request_type and request_last
  are per channel, set by its last DMAWFP, and are single and cleared
  when the channel starts.  A peripheral request interface belongs to
  one channel: several channels waiting on one interface at once is
  abnormal use, and which of them and how many a request serves is
  undefined (the Zynq-7000's wakes them all on one request, this one
  serves the next its scan visits).  Every DMALDP and DMASTP acknowledges
  once; the Zynq-7000's was seen losing one of two acknowledges
  completing close together.  DMAFLUSHP does not wait for
  the channel's transfers: its flush request can overtake the
  acknowledge of a DMALDP or DMASTP still in flight, which a barrier
  before it prevents.

AXI
  One read burst and one write burst in flight at most, write data
  only after the write address is accepted.

Events
  Each event-interrupt resource has one INT_EVENT_RIS bit, as on the
  Zynq-7000's DMA-330: DMASEV sets it when INTEN selects the interrupt
  or when no thread waits; enabling INTEN turns a pending event into an
  interrupt, INTCLR clears it either way, a DMAWFE takes it only when
  INTEN does not select it.  An event with its interrupt enabled
  raises the interrupt and wakes no thread.  A DMASEV wakes every thread waiting for its event at that
  time; a woken thread does not wait anymore, so another DMASEV before
  it runs again leaves the event pending.  Instructions execute one at
  a time: a DMASEV and a DMAWFE never happen together, the later one
  sees the effect of the earlier.

Debug instructions
  Only DMAGO (to the manager), DMASEV and DMAKILL execute; any other
  instruction, DMAGO to a channel thread and undefined encodings
  included, is ignored, as the Zynq-7000's DMA-330 does.  They execute
  whatever the thread's state, a faulting one included.  Invalid
  operands (a DMASEV beyond the events, a DMAGO beyond the channels or
  with reserved bits set) are ignored too, as on the Zynq-7000's, so
  nothing faults a thread through the debug registers and FTR's
  dbg_instr never sets.  A debug instruction to a channel beyond the
  channel count is ignored.  DBGCMD decodes bit 0 only (0 and 2
  execute, 1 and 3 do not), as the Zynq-7000's DMA-330 does.  A DBGCMD
  written while DBGSTATUS is busy is queued with DBGINST0/1 as they are
  then, and executes after the previous instruction: back-to-back
  commands both execute, as on the Zynq-7000's.  A third one, written
  while one executes and one is queued, is ignored.  DBGINST0/1 writes
  while busy do not affect the instructions executing or queued.

Registers
  Registers change at instruction boundaries.  Channel registers read
  as the last write-back left them, at most one instruction stale; two
  read one after the other may straddle a write-back.  As on the Zynq-7000's DMA-330, the PC of a thread is
  past a waiting instruction (DMAWFE, DMAWFP, barriers, discontinuous
  DMAMOV) as soon as it executes, past DMAEND and DMAKILL once stopped,
  on an instruction that faulted precisely.  CSR's and DSR's wakeup
  number is the last wait's while the thread waits and after a kill
  interrupted the wait, a later DMAGO included, zero once a wait
  resolved (at once for a pending event or a request already there);
  CSR's dmawfp_b_ns is set by DMAWFP burst and periph.  Faults are cleared when the thread is killed, as it
  leaves the faulting state.  Write-only registers (INTCLR, DBGCMD,
  DBGINST0/1) and reserved offsets read as zero, writes to reserved
  offsets are ignored, as on the Zynq-7000's.  WD reads back what was written and has no
  effect: fixed MFIFO shares cannot lock up.

Verification
============

The regression (``tests/amba/axi_m2m_dma``) follows scripts that the
DMA's reference model, in the fpix project, generates: directed and
seeded random programs, the transfers, acknowledges, registers and
memory the model expects of them, and their synchronization
constraints.  The bench drives the DMA through its APB slave only
(debug instructions, register reads, interrupt registers) and resets it
to run manager programs from the boot address.  The scripts are
committed; each one's header says how to regenerate it.

Program assembly
================

The package provides functions returning the encoding of each
instruction as a byte string (``asm_mov_ccr``, ``asm_ld``,
``asm_lp``, ``asm_lpend``, ...) and ``ccr_value`` to build a CCR
value, so that test benches can build programs by concatenation:

.. code:: vhdl

   constant body_c : byte_string := asm_ld & asm_st;
   constant prog_c : byte_string :=
     asm_mov_ccr(ccr_value(src_size_l2 => 2, src_len => 4,
                           dst_size_l2 => 2, dst_len => 4))
     & asm_mov_sar(x"00001000")
     & asm_mov_dar(x"00002000")
     & asm_lp(0, 4) & body_c & asm_lpend(0, body_c'length)
     & asm_end;
