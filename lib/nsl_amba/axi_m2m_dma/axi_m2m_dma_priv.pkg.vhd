library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_data.bytestream.all;

-- Internals of axi_m2m_microcoded_dma.
--
-- The controller is split in four blocks:
--
-- * the thread engine holds every channel's context in a memory,
--   fetches and executes instructions of one channel at a time, and
--   hands load and store transfers to the reader and the writer,
--
-- * the reader owns the AXI read channels, performs instruction
--   fetches and load bursts, and appends loaded bytes to the channel's
--   MFIFO,
--
-- * the writer owns the AXI write channels, waits for all the data of
--   a store burst to be in the MFIFO, and performs the burst,
--
-- * the peripheral block holds the peripheral request interfaces:
--   request FIFOs, flush state and acknowledge outputs,
--
-- * the register file is the APB slave: it holds the registers the
--   host writes, issues debug instructions to the thread engine and
--   reads thread registers through it.
--
-- The MFIFO is one byte-wide RAM per data bus byte lane.  Byte n of a
-- channel's stream lives in lane n mod W, at word n / W of the
-- channel's region, so that any W consecutive stream bytes sit in
-- distinct lanes, at most one word apart: pushing or popping up to W
-- bytes at any stream position is one access per lane, each lane with
-- its own address.
--
-- Stream positions are counted by free-running byte pointers per
-- channel, all reset when the channel starts: the thread engine
-- counts bytes promised by executed loads (ld_ptr) and claimed by
-- executed stores (st_ptr), the reader counts bytes pushed (write
-- pointer), the writer counts bytes popped (read pointer).
package axi_m2m_dma_priv is

  constant max_bus_bytes_l2_c : natural := 4;
  constant max_bus_bytes_c : natural := 2**max_bus_bytes_l2_c;

  subtype channel_t is unsigned(2 downto 0);
  subtype periph_t is unsigned(4 downto 0);

  -- MFIFO byte pointer, wrapping.  Only differences between pointers
  -- of a channel are meaningful; they never exceed twice the channel
  -- MFIFO size, which is at most 4 kB.  With a channel MFIFO of
  -- 2**cap_l2 bytes, pointers wrap at 2**(cap_l2 + 2) (see
  -- ptr_wrap()), bits above are zero.
  subtype ptr_t is unsigned(15 downto 0);
  type ptr_vector is array (natural range <>) of ptr_t;
  constant max_mfifo_channel_bytes_l2_c : natural := 12;

  subtype lane_addr_t is unsigned(15 downto 0);
  type lane_addr_vector is array (natural range <>) of lane_addr_t;

  -- Load or store transfer, from thread engine to reader or writer.
  -- bytes is the byte count the burst transfers.  zero is DMASTZ.
  -- swap_l2 is a store's endian swap size (log2 of bytes in a swapped
  -- group).
  -- ack requests a peripheral acknowledge of type single or burst
  -- (ack_burst) to periph once the transfer completed.
  type transfer_t is
  record
    valid: std_ulogic;
    channel: channel_t;
    addr: unsigned(31 downto 0);
    size_l2: unsigned(2 downto 0);
    len_m1: unsigned(3 downto 0);
    incr: std_ulogic;
    cache: std_ulogic_vector(3 downto 0);
    prot: std_ulogic_vector(2 downto 0);
    bytes: unsigned(8 downto 0);
    zero: std_ulogic;
    swap_l2: unsigned(2 downto 0);
    ack: std_ulogic;
    ack_burst: std_ulogic;
    periph: periph_t;
  end record;

  -- Instruction fetch of one data bus word at a bus-aligned address,
  -- for the manager thread when manager is set, for channel "channel"
  -- otherwise.
  type fetch_request_t is
  record
    valid: std_ulogic;
    manager: std_ulogic;
    channel: channel_t;
    addr: unsigned(31 downto 0);
  end record;

  -- Fetch response, valid for one cycle.
  type fetch_response_t is
  record
    valid: std_ulogic;
    error: std_ulogic;
    data: byte_string(0 to max_bus_bytes_c-1);
  end record;

  -- Acknowledge request to the peripheral block.  The source holds
  -- valid and payload until a cycle where the matching grant is set,
  -- which is when the acknowledge is taken.
  type ack_request_t is
  record
    valid: std_ulogic;
    periph: periph_t;
    atype: nsl_amba.dma_request.request_type_t;
  end record;

  -- Head of a peripheral request FIFO.
  type request_state_t is
  record
    valid: std_ulogic;
    burst: std_ulogic;
    last: std_ulogic;
  end record;
  type request_state_vector is array (natural range <>) of request_state_t;

  -- Channel registers the thread engine reads for the register file:
  -- the DMA-330 channel registers of these names.
  type channel_register_t is (
    CHANNEL_CSR,
    CHANNEL_CPC,
    CHANNEL_SAR,
    CHANNEL_DAR,
    CHANNEL_CCR,
    CHANNEL_LC0,
    CHANNEL_LC1,
    CHANNEL_FTR
    );

  -- Channel register read request.  valid/ready handshake.
  type status_request_t is
  record
    valid: std_ulogic;
    channel: channel_t;
    reg: channel_register_t;
  end record;

  -- Channel register value, valid for one cycle, answering requests in
  -- order.  A channel beyond the channel count reads as zero.
  type status_response_t is
  record
    valid: std_ulogic;
    data: std_ulogic_vector(31 downto 0);
  end record;

  -- Instruction issued through the debug registers.  valid/ready
  -- handshake; the thread engine holds ready low until the instruction
  -- executed.  channel_thread and channel are DBGINST0's debug thread
  -- and channel number, inst the instruction bytes 0 to 5.
  type debug_request_t is
  record
    valid: std_ulogic;
    channel_thread: std_ulogic;
    channel: channel_t;
    inst: byte_string(0 to 5);
  end record;

  -- Manager thread registers: DSR state [3:0] and wakeup event [8:4],
  -- DPC, FTRD.
  type manager_status_t is
  record
    state: nsl_amba.axi_m2m_dma.channel_state_t;
    wakeup: unsigned(4 downto 0);
    pc: unsigned(31 downto 0);
    fault: std_ulogic_vector(31 downto 0);
  end record;

  -- Pointer p wrapped for a channel MFIFO of 2**cap_l2 bytes
  function ptr_wrap(p : unsigned; cap_l2 : natural) return ptr_t;
  -- Sign bit of a wrapped pointer difference
  function ptr_negative(d : ptr_t; cap_l2 : natural) return boolean;

  -- Mask of the byte offset within a beat of 2**size_l2 bytes.
  function size_mask(size_l2 : unsigned(2 downto 0)) return unsigned;
  -- 2**size_l2
  function size_bytes(size_l2 : unsigned(2 downto 0)) return unsigned;

  component axi_m2m_dma_thread is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      channel_count_c : positive;
      event_count_c : positive;
      peripheral_count_c : positive;
      mfifo_depth_l2_c : positive;
      endian_swap_c : boolean;
      failed_store_fault_c : boolean;
      boot_from_pc_c : boolean;
      boot_addr_c : unsigned(31 downto 0)
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      debug_i : in debug_request_t;
      debug_ready_o : out std_ulogic;
      status_i : in status_request_t;
      status_ready_o : out std_ulogic;
      status_o : out status_response_t;
      manager_o : out manager_status_t;
      faulting_o : out std_ulogic_vector(0 to channel_count_c-1);
      events_o : out std_ulogic_vector(event_count_c-1 downto 0);

      irq_enable_i : in std_ulogic_vector(event_count_c-1 downto 0);
      irq_clear_i : in std_ulogic_vector(event_count_c-1 downto 0);
      irq_o : out std_ulogic_vector(event_count_c-1 downto 0);
      irq_abort_o : out std_ulogic;

      fetch_o : out fetch_request_t;
      fetch_ready_i : in std_ulogic;
      fetch_i : in fetch_response_t;

      load_o : out transfer_t;
      load_ready_i : in std_ulogic;
      store_o : out transfer_t;
      store_ready_i : in std_ulogic;

      read_busy_i : in std_ulogic_vector(0 to channel_count_c-1);
      write_busy_i : in std_ulogic_vector(0 to channel_count_c-1);
      read_error_i : in std_ulogic_vector(0 to channel_count_c-1);
      write_error_i : in std_ulogic_vector(0 to channel_count_c-1);
      released_i : in ptr_vector(0 to channel_count_c-1);
      pushed_i : in ptr_vector(0 to channel_count_c-1);
      poisoned_i : in std_ulogic_vector(0 to channel_count_c-1);
      poison_i : in ptr_vector(0 to channel_count_c-1);
      abort_o : out std_ulogic_vector(0 to channel_count_c-1);
      clear_o : out std_ulogic_vector(0 to channel_count_c-1);

      request_i : in request_state_vector(0 to peripheral_count_c-1);
      pop_o : out std_ulogic_vector(0 to peripheral_count_c-1);
      flush_o : out ack_request_t;
      flush_grant_i : in std_ulogic
      );
  end component;

  component axi_m2m_dma_registers is
    generic(
      apb_config_c : nsl_amba.apb.config_t;
      channel_count_c : positive;
      event_count_c : positive;
      peripheral_count_c : positive;
      mfifo_lines_c : positive;
      bus_bytes_l2_c : natural;
      boot_from_pc_c : boolean;
      boot_addr_c : unsigned(31 downto 0)
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t;

      debug_o : out debug_request_t;
      debug_ready_i : in std_ulogic;
      status_o : out status_request_t;
      status_ready_i : in std_ulogic;
      status_i : in status_response_t;
      manager_i : in manager_status_t;
      faulting_i : in std_ulogic_vector(0 to channel_count_c-1);
      events_i : in std_ulogic_vector(event_count_c-1 downto 0);
      irq_i : in std_ulogic_vector(event_count_c-1 downto 0);

      irq_enable_o : out std_ulogic_vector(event_count_c-1 downto 0);
      irq_clear_o : out std_ulogic_vector(event_count_c-1 downto 0)
      );
  end component;

  component axi_m2m_dma_reader is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      channel_count_c : positive;
      mfifo_depth_l2_c : positive;
      failed_store_fault_c : boolean
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      ar_o : out nsl_amba.axi4_mm.address_t;
      ar_i : in nsl_amba.axi4_mm.handshake_t;
      r_o : out nsl_amba.axi4_mm.handshake_t;
      r_i : in nsl_amba.axi4_mm.read_data_t;

      fetch_i : in fetch_request_t;
      fetch_ready_o : out std_ulogic;
      fetch_o : out fetch_response_t;

      load_i : in transfer_t;
      load_ready_o : out std_ulogic;

      busy_o : out std_ulogic_vector(0 to channel_count_c-1);
      error_o : out std_ulogic_vector(0 to channel_count_c-1);
      abort_i : in std_ulogic_vector(0 to channel_count_c-1);
      clear_i : in std_ulogic_vector(0 to channel_count_c-1);
      pushed_o : out ptr_vector(0 to channel_count_c-1);
      poisoned_o : out std_ulogic_vector(0 to channel_count_c-1);
      poison_o : out ptr_vector(0 to channel_count_c-1);

      mfifo_address_o : out lane_addr_vector(0 to 2**config_c.data_bus_width_l2-1);
      mfifo_enable_o : out std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
      mfifo_data_o : out byte_string(0 to 2**config_c.data_bus_width_l2-1);

      ack_o : out ack_request_t;
      ack_grant_i : in std_ulogic
      );
  end component;

  component axi_m2m_dma_writer is
    generic(
      config_c : nsl_amba.axi4_mm.config_t;
      channel_count_c : positive;
      mfifo_depth_l2_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      aw_o : out nsl_amba.axi4_mm.address_t;
      aw_i : in nsl_amba.axi4_mm.handshake_t;
      w_o : out nsl_amba.axi4_mm.write_data_t;
      w_i : in nsl_amba.axi4_mm.handshake_t;
      b_o : out nsl_amba.axi4_mm.handshake_t;
      b_i : in nsl_amba.axi4_mm.write_response_t;

      store_i : in transfer_t;
      store_ready_o : out std_ulogic;

      busy_o : out std_ulogic_vector(0 to channel_count_c-1);
      error_o : out std_ulogic_vector(0 to channel_count_c-1);
      abort_i : in std_ulogic_vector(0 to channel_count_c-1);
      clear_i : in std_ulogic_vector(0 to channel_count_c-1);
      pushed_i : in ptr_vector(0 to channel_count_c-1);
      popped_o : out ptr_vector(0 to channel_count_c-1);

      mfifo_address_o : out lane_addr_vector(0 to 2**config_c.data_bus_width_l2-1);
      mfifo_enable_o : out std_ulogic;
      mfifo_data_i : in byte_string(0 to 2**config_c.data_bus_width_l2-1);

      ack_o : out ack_request_t;
      ack_grant_i : in std_ulogic
      );
  end component;

  component axi_m2m_dma_peripheral is
    generic(
      peripheral_count_c : positive;
      request_depth_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      periph_i : in nsl_amba.dma_request.peripheral_vector(0 to peripheral_count_c-1);
      periph_o : out nsl_amba.dma_request.dmac_vector(0 to peripheral_count_c-1);

      request_o : out request_state_vector(0 to peripheral_count_c-1);
      pop_i : in std_ulogic_vector(0 to peripheral_count_c-1);

      flush_i : in ack_request_t;
      flush_grant_o : out std_ulogic;
      read_ack_i : in ack_request_t;
      read_grant_o : out std_ulogic;
      write_ack_i : in ack_request_t;
      write_grant_o : out std_ulogic
      );
  end component;

end package;

package body axi_m2m_dma_priv is

  function ptr_wrap(p : unsigned; cap_l2 : natural) return ptr_t
  is
    variable ret : ptr_t := resize(p, ptr_t'length);
  begin
    ret(ret'left downto cap_l2 + 2) := (others => '0');
    return ret;
  end function;

  function ptr_negative(d : ptr_t; cap_l2 : natural) return boolean
  is
  begin
    return d(cap_l2 + 1) = '1';
  end function;

  function size_mask(size_l2 : unsigned(2 downto 0)) return unsigned
  is
    variable ret : unsigned(max_bus_bytes_l2_c-1 downto 0) := (others => '0');
  begin
    for i in ret'range
    loop
      if i < to_integer(size_l2) then
        ret(i) := '1';
      end if;
    end loop;
    return ret;
  end function;

  function size_bytes(size_l2 : unsigned(2 downto 0)) return unsigned
  is
    variable ret : unsigned(max_bus_bytes_l2_c downto 0) := (others => '0');
  begin
    for i in ret'range
    loop
      if i = to_integer(size_l2) then
        ret(i) := '1';
      end if;
    end loop;
    return ret;
  end function;

end package body;
