library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.axi_m2m_dma_priv.all;
use nsl_data.bytestream.all;

-- APB register file of axi_m2m_microcoded_dma, the DMA-330's layout.
--
-- No access waits on the thread engine, which may itself wait on an
-- access to these registers (a channel loading or storing them through
-- an interconnect shared with the host): every access completes in a
-- bounded number of cycles.
--
-- Registers the host writes live here: INTEN, WD, DBGINST0/1.  INTCLR
-- is a one-cycle clear pulse to the thread engine.  A DBGCMD write
-- with bit 0 clear hands DBGINST0/1 to the thread engine (the DMA-330
-- of the Zynq-7000 decodes bit 0 only: 0 and 2 execute) if the debug
-- interface is idle, or queues them if it is busy with one instruction
-- only, so that back-to-back commands both execute, as on the Zynq's;
-- with a second one already queued, or bit 0 set, it is ignored.
-- DBGSTATUS reads busy while an instruction is queued or not executed
-- yet.
--
-- Manager, fault summary and event registers come from thread engine
-- outputs.  Channel registers (FTRn, CSRn, CPCn, SARn, DARn, CCRn,
-- LC0_n, LC1_n) are read through the engine's register read port,
-- which answers in a fixed number of cycles from its own copy of the
-- context memory.  Write-only and reserved registers read as zero,
-- writes to read-only and reserved registers are ignored.
entity axi_m2m_dma_registers is
  generic(
    apb_config_c : nsl_amba.apb.config_t;
    channel_count_c : positive;
    event_count_c : positive;
    peripheral_count_c : positive;
    -- MFIFO depth in data bus words, all channels
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
end entity;

architecture beh of axi_m2m_dma_registers is

  constant reg_count_l2_c : natural := 10;
  subtype reg_no_t is integer range 0 to 2**reg_count_l2_c-1;
  subtype word_t is unsigned(31 downto 0);

  -- Channel register read in progress: request handed to the engine,
  -- waiting for its answer, answer held until the bus takes it.
  type read_state_t is (
    READ_IDLE,
    READ_REQUEST,
    READ_WAIT,
    READ_DONE
    );

  type regs_t is
  record
    inten: std_ulogic_vector(event_count_c-1 downto 0);
    clear: std_ulogic_vector(event_count_c-1 downto 0);
    wd_irq_only: std_ulogic;
    dbginst0: word_t;
    dbginst1: word_t;
    -- DBGCMD written, not taken by the engine yet, from the queue when
    -- dbg_queued
    dbg_pending: std_ulogic;
    dbg_queued: boolean;
    -- DBGINST0/1 of a DBGCMD written while busy
    q_valid: std_ulogic;
    q_inst0: word_t;
    q_inst1: word_t;
    read: read_state_t;
    sreq: status_request_t;
    rdata: std_ulogic_vector(31 downto 0);
  end record;

  signal r, rin: regs_t;

  signal reg_no_s : reg_no_t;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s, r_strobe_s, r_valid_s : std_ulogic;

  -- Channel register at register number reg (byte offset / 4), if any
  function is_channel_register(reg : reg_no_t) return boolean is
  begin
    case reg is
      when 16#10# to 16#17# | 16#40# to 16#4f# =>
        return true;
      when 16#100# to 16#13f# =>
        return (reg mod 8) <= 4;
      when others =>
        return false;
    end case;
  end function;

  function channel_register(reg : reg_no_t) return status_request_t is
    variable ret : status_request_t := (valid => '1', channel => (others => '0'), reg => CHANNEL_CSR);
  begin
    case reg is
      when 16#10# to 16#17# =>
        ret.channel := to_unsigned(reg - 16#10#, 3);
        ret.reg := CHANNEL_FTR;
      when 16#40# to 16#4f# =>
        ret.channel := to_unsigned((reg - 16#40#) / 2, 3);
        if reg mod 2 = 0 then
          ret.reg := CHANNEL_CSR;
        else
          ret.reg := CHANNEL_CPC;
        end if;
      when others =>
        ret.channel := to_unsigned(((reg - 16#100#) / 8) mod 8, 3);
        case reg mod 8 is
          when 0 => ret.reg := CHANNEL_SAR;
          when 1 => ret.reg := CHANNEL_DAR;
          when 2 => ret.reg := CHANNEL_CCR;
          when 3 => ret.reg := CHANNEL_LC0;
          when others => ret.reg := CHANNEL_LC1;
        end case;
    end case;
    return ret;
  end function;

  function busy(r : regs_t; debug_ready : std_ulogic) return boolean is
  begin
    return r.dbg_pending = '1' or r.q_valid = '1' or debug_ready = '0';
  end function;

  function min(a, b : natural) return natural is
  begin
    if a < b then
      return a;
    end if;
    return b;
  end function;

  function cr0_value return word_t is
    variable ret : word_t := (others => '0');
  begin
    ret(21 downto 17) := to_unsigned(event_count_c - 1, 5);
    ret(16 downto 12) := to_unsigned(peripheral_count_c - 1, 5);
    ret(6 downto 4) := to_unsigned(channel_count_c - 1, 3);
    if boot_from_pc_c then
      ret(1) := '1';
    end if;
    ret(0) := '1';
    return ret;
  end function;

  -- One instruction line of one data bus word
  constant cr1_c : word_t := to_unsigned(bus_bytes_l2_c, 32);
  -- One-deep read and write queues, one read and one write in flight
  constant crd_c : word_t := to_unsigned(min(mfifo_lines_c, 1024) - 1, 12)
                             & x"0000" & to_unsigned(bus_bytes_l2_c, 4);

begin

  assert apb_config_c.data_bus_width_l2 = 2
    report "axi_m2m_microcoded_dma needs a 32-bit APB"
    severity failure;

  assert apb_config_c.address_width >= 12
    report "axi_m2m_microcoded_dma needs 12 bits of APB address"
    severity failure;

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => apb_config_c,
      reg_count_l2_c => reg_count_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s,

      r_valid_i => r_valid_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.inten <= (others => '0');
      r.clear <= (others => '0');
      r.wd_irq_only <= '0';
      r.dbginst0 <= (others => '0');
      r.dbginst1 <= (others => '0');
      r.dbg_pending <= '0';
      r.q_valid <= '0';
      r.read <= READ_IDLE;
      r.sreq.valid <= '0';
    end if;
  end process;

  transition: process(r, reg_no_s, w_value_s, w_strobe_s, r_strobe_s,
                      debug_ready_i, status_ready_i, status_i) is
  begin
    rin <= r;

    rin.clear <= (others => '0');

    if r.dbg_pending = '1' and debug_ready_i = '1' then
      rin.dbg_pending <= '0';
    elsif r.dbg_pending = '0' and r.q_valid = '1' and debug_ready_i = '1' then
      rin.dbg_pending <= '1';
      rin.dbg_queued <= true;
      rin.q_valid <= '0';
    end if;

    if w_strobe_s = '1' then
      case reg_no_s * 4 is
        when reg_inten_c =>
          rin.inten <= std_ulogic_vector(w_value_s(event_count_c-1 downto 0));
        when reg_intclr_c =>
          rin.clear <= std_ulogic_vector(w_value_s(event_count_c-1 downto 0));
        when reg_wd_c =>
          rin.wd_irq_only <= w_value_s(0);
        when reg_dbginst0_c =>
          rin.dbginst0 <= w_value_s;
        when reg_dbginst1_c =>
          rin.dbginst1 <= w_value_s;
        when reg_dbgcmd_c =>
          if w_value_s(0) = '0' then
            if not busy(r, debug_ready_i) then
              -- Taken the next cycle, before DBGINST0/1 can change
              rin.dbg_pending <= '1';
              rin.dbg_queued <= false;
            elsif r.q_valid = '0' then
              rin.q_valid <= '1';
              rin.q_inst0 <= r.dbginst0;
              rin.q_inst1 <= r.dbginst1;
            end if;
          end if;
        when others =>
          null;
      end case;
    end if;

    case r.read is
      when READ_IDLE =>
        if r_strobe_s = '1' and is_channel_register(reg_no_s) then
          rin.sreq <= channel_register(reg_no_s);
          rin.read <= READ_REQUEST;
        end if;

      when READ_REQUEST =>
        if status_ready_i = '1' then
          rin.sreq.valid <= '0';
          rin.read <= READ_WAIT;
        end if;

      when READ_WAIT =>
        if status_i.valid = '1' then
          rin.rdata <= status_i.data;
          rin.read <= READ_DONE;
        end if;

      when READ_DONE =>
        if r_strobe_s = '1' then
          rin.read <= READ_IDLE;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable inst0, inst1 : word_t;
  begin
    irq_enable_o <= r.inten;
    irq_clear_o <= r.clear;
    status_o <= r.sreq;

    if r.dbg_queued then
      inst0 := r.q_inst0;
      inst1 := r.q_inst1;
    else
      inst0 := r.dbginst0;
      inst1 := r.dbginst1;
    end if;
    debug_o.valid <= r.dbg_pending;
    debug_o.channel_thread <= inst0(0);
    debug_o.channel <= inst0(10 downto 8);
    debug_o.inst(0) <= std_ulogic_vector(inst0(23 downto 16));
    debug_o.inst(1) <= std_ulogic_vector(inst0(31 downto 24));
    for i in 0 to 3
    loop
      debug_o.inst(2 + i) <= std_ulogic_vector(inst1(8*i+7 downto 8*i));
    end loop;
  end process;

  mealy: process(r, reg_no_s, debug_ready_i, manager_i, faulting_i, events_i, irq_i) is
    variable v : word_t;
  begin
    v := (others => '0');
    r_valid_s <= '1';

    if is_channel_register(reg_no_s) then
      v := unsigned(r.rdata);
      if r.read /= READ_DONE then
        r_valid_s <= '0';
      end if;
    else
      case reg_no_s * 4 is
        when reg_dsr_c =>
          v(8 downto 4) := manager_i.wakeup;
          v(3 downto 0) := unsigned(manager_i.state);
        when reg_dpc_c =>
          v := manager_i.pc;
        when reg_inten_c =>
          v(event_count_c-1 downto 0) := unsigned(r.inten);
        when reg_int_event_ris_c =>
          v(event_count_c-1 downto 0) := unsigned(events_i);
        when reg_intmis_c =>
          v(event_count_c-1 downto 0) := unsigned(irq_i);
        when reg_fsrd_c =>
          if manager_i.state = channel_faulting_c then
            v(0) := '1';
          end if;
        when reg_fsrc_c =>
          for c in 0 to channel_count_c-1
          loop
            v(c) := faulting_i(c);
          end loop;
        when reg_ftrd_c =>
          v := unsigned(manager_i.fault);
        when reg_dbgstatus_c =>
          if busy(r, debug_ready_i) then
            v(0) := '1';
          end if;
        when reg_cr0_c =>
          v := cr0_value;
        when reg_cr1_c =>
          v := cr1_c;
        when reg_cr2_c =>
          v := boot_addr_c;
        when reg_crd_c =>
          v := crd_c;
        when reg_wd_c =>
          v(0) := r.wd_irq_only;
        when reg_periph_id0_c => v(7 downto 0) := periph_id_c(7 downto 0);
        when reg_periph_id0_c + 4 => v(7 downto 0) := periph_id_c(15 downto 8);
        when reg_periph_id0_c + 8 => v(7 downto 0) := periph_id_c(23 downto 16);
        when reg_periph_id0_c + 12 => v(7 downto 0) := periph_id_c(31 downto 24);
        when reg_pcell_id0_c => v(7 downto 0) := pcell_id_c(7 downto 0);
        when reg_pcell_id0_c + 4 => v(7 downto 0) := pcell_id_c(15 downto 8);
        when reg_pcell_id0_c + 8 => v(7 downto 0) := pcell_id_c(23 downto 16);
        when reg_pcell_id0_c + 12 => v(7 downto 0) := pcell_id_c(31 downto 24);
        when others =>
          null;
      end case;
    end if;

    r_value_s <= v;
  end process;

end architecture;
