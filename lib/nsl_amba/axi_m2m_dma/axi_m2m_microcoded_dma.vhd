library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_memory;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_amba.axi_m2m_dma_priv.all;
use nsl_data.bytestream.all;

entity axi_m2m_microcoded_dma is
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
end entity;

architecture beh of axi_m2m_microcoded_dma is

  constant bus_l2_c : natural := config_c.data_bus_width_l2;
  constant bus_bytes_c : natural := 2**bus_l2_c;
  constant channel_l2_c : natural := nsl_math.arith.log2(channel_count_c);
  constant lane_addr_size_c : natural := channel_l2_c + mfifo_depth_l2_c;

  signal debug_s : debug_request_t;
  signal debug_ready_s : std_ulogic;
  signal status_req_s : status_request_t;
  signal status_ready_s : std_ulogic;
  signal status_rsp_s : status_response_t;
  signal manager_s : manager_status_t;
  signal faulting_s : std_ulogic_vector(0 to channel_count_c-1);
  signal events_s, irq_enable_s, irq_clear_s, irq_s : std_ulogic_vector(event_count_c-1 downto 0);

  signal fetch_req_s : fetch_request_t;
  signal fetch_ready_s : std_ulogic;
  signal fetch_rsp_s : fetch_response_t;
  signal load_s, store_s : transfer_t;
  signal load_ready_s, store_ready_s : std_ulogic;
  signal read_busy_s, write_busy_s, read_error_s, write_error_s : std_ulogic_vector(0 to channel_count_c-1);
  signal abort_s, clear_s : std_ulogic_vector(0 to channel_count_c-1);
  signal pushed_s, popped_s, poison_s : ptr_vector(0 to channel_count_c-1);
  signal poisoned_s : std_ulogic_vector(0 to channel_count_c-1);
  signal request_s : request_state_vector(0 to peripheral_count_c-1);
  signal pop_s : std_ulogic_vector(0 to peripheral_count_c-1);
  signal flush_s, read_ack_s, write_ack_s : ack_request_t;
  signal flush_grant_s, read_grant_s, write_grant_s : std_ulogic;

  signal mfifo_waddr_s, mfifo_raddr_s : lane_addr_vector(0 to bus_bytes_c-1);
  signal mfifo_wen_s : std_ulogic_vector(0 to bus_bytes_c-1);
  signal mfifo_ren_s : std_ulogic;
  signal mfifo_wdata_s, mfifo_rdata_s : byte_string(0 to bus_bytes_c-1);

begin

  assert config_c.address_width = 32
    report "axi_m2m_microcoded_dma needs 32-bit addresses"
    severity failure;

  assert bus_l2_c >= 2 and bus_l2_c <= max_bus_bytes_l2_c
    report "axi_m2m_microcoded_dma needs a 32 to 128-bit data bus"
    severity failure;

  assert config_c.len_width >= 4 and config_c.has_burst and config_c.has_size
    report "axi_m2m_microcoded_dma needs bursts of up to 16 beats and size"
    severity failure;

  assert config_c.id_width = 0 or 2**config_c.id_width > channel_count_c
    report "AXI ID too narrow for the channel and manager threads"
    severity failure;

  registers: nsl_amba.axi_m2m_dma_priv.axi_m2m_dma_registers
    generic map(
      apb_config_c => apb_config_c,
      channel_count_c => channel_count_c,
      event_count_c => event_count_c,
      peripheral_count_c => peripheral_count_c,
      mfifo_lines_c => channel_count_c * 2**mfifo_depth_l2_c,
      bus_bytes_l2_c => bus_l2_c,
      boot_from_pc_c => boot_from_pc_c,
      boot_addr_c => boot_addr_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      debug_o => debug_s,
      debug_ready_i => debug_ready_s,
      status_o => status_req_s,
      status_ready_i => status_ready_s,
      status_i => status_rsp_s,
      manager_i => manager_s,
      faulting_i => faulting_s,
      events_i => events_s,
      irq_i => irq_s,

      irq_enable_o => irq_enable_s,
      irq_clear_o => irq_clear_s
      );

  irq_o <= irq_s;

  thread: nsl_amba.axi_m2m_dma_priv.axi_m2m_dma_thread
    generic map(
      config_c => config_c,
      channel_count_c => channel_count_c,
      event_count_c => event_count_c,
      peripheral_count_c => peripheral_count_c,
      mfifo_depth_l2_c => mfifo_depth_l2_c,
      endian_swap_c => endian_swap_c,
      failed_store_fault_c => failed_store_fault_c,
      boot_from_pc_c => boot_from_pc_c,
      boot_addr_c => boot_addr_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      debug_i => debug_s,
      debug_ready_o => debug_ready_s,
      status_i => status_req_s,
      status_ready_o => status_ready_s,
      status_o => status_rsp_s,
      manager_o => manager_s,
      faulting_o => faulting_s,
      events_o => events_s,

      irq_enable_i => irq_enable_s,
      irq_clear_i => irq_clear_s,
      irq_o => irq_s,
      irq_abort_o => irq_abort_o,

      fetch_o => fetch_req_s,
      fetch_ready_i => fetch_ready_s,
      fetch_i => fetch_rsp_s,

      load_o => load_s,
      load_ready_i => load_ready_s,
      store_o => store_s,
      store_ready_i => store_ready_s,

      read_busy_i => read_busy_s,
      write_busy_i => write_busy_s,
      read_error_i => read_error_s,
      write_error_i => write_error_s,
      released_i => popped_s,
      pushed_i => pushed_s,
      poisoned_i => poisoned_s,
      poison_i => poison_s,
      abort_o => abort_s,
      clear_o => clear_s,

      request_i => request_s,
      pop_o => pop_s,
      flush_o => flush_s,
      flush_grant_i => flush_grant_s
      );

  reader: nsl_amba.axi_m2m_dma_priv.axi_m2m_dma_reader
    generic map(
      config_c => config_c,
      channel_count_c => channel_count_c,
      mfifo_depth_l2_c => mfifo_depth_l2_c,
      failed_store_fault_c => failed_store_fault_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      ar_o => axi_o.ar,
      ar_i => axi_i.ar,
      r_o => axi_o.r,
      r_i => axi_i.r,

      fetch_i => fetch_req_s,
      fetch_ready_o => fetch_ready_s,
      fetch_o => fetch_rsp_s,

      load_i => load_s,
      load_ready_o => load_ready_s,

      busy_o => read_busy_s,
      error_o => read_error_s,
      abort_i => abort_s,
      clear_i => clear_s,
      pushed_o => pushed_s,
      poisoned_o => poisoned_s,
      poison_o => poison_s,

      mfifo_address_o => mfifo_waddr_s,
      mfifo_enable_o => mfifo_wen_s,
      mfifo_data_o => mfifo_wdata_s,

      ack_o => read_ack_s,
      ack_grant_i => read_grant_s
      );

  writer: nsl_amba.axi_m2m_dma_priv.axi_m2m_dma_writer
    generic map(
      config_c => config_c,
      channel_count_c => channel_count_c,
      mfifo_depth_l2_c => mfifo_depth_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      aw_o => axi_o.aw,
      aw_i => axi_i.aw,
      w_o => axi_o.w,
      w_i => axi_i.w,
      b_o => axi_o.b,
      b_i => axi_i.b,

      store_i => store_s,
      store_ready_o => store_ready_s,

      busy_o => write_busy_s,
      error_o => write_error_s,
      abort_i => abort_s,
      clear_i => clear_s,
      pushed_i => pushed_s,
      popped_o => popped_s,

      mfifo_address_o => mfifo_raddr_s,
      mfifo_enable_o => mfifo_ren_s,
      mfifo_data_i => mfifo_rdata_s,

      ack_o => write_ack_s,
      ack_grant_i => write_grant_s
      );

  peripheral: nsl_amba.axi_m2m_dma_priv.axi_m2m_dma_peripheral
    generic map(
      peripheral_count_c => peripheral_count_c,
      request_depth_c => request_depth_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      periph_i => periph_i,
      periph_o => periph_o,

      request_o => request_s,
      pop_i => pop_s,

      flush_i => flush_s,
      flush_grant_o => flush_grant_s,
      read_ack_i => read_ack_s,
      read_grant_o => read_grant_s,
      write_ack_i => write_ack_s,
      write_grant_o => write_grant_s
      );

  lanes: for l in 0 to bus_bytes_c-1
  generate
    lane: nsl_memory.ram.ram_auto
      generic map(
        addr_size_c => lane_addr_size_c,
        word_size_c => 8,
        data_word_count_c => 1
        )
      port map(
        clock_i => clock_i,

        write_address_i => mfifo_waddr_s(l)(lane_addr_size_c-1 downto 0),
        write_en_i(0) => mfifo_wen_s(l),
        write_data_i => mfifo_wdata_s(l),

        read_address_i => mfifo_raddr_s(l)(lane_addr_size_c-1 downto 0),
        read_en_i => mfifo_ren_s,
        read_data_o => mfifo_rdata_s(l)
        );
  end generate;

end architecture;
