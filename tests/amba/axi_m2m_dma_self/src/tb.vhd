library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

-- Two APB masters sharing one slave, one transfer at a time, as an
-- interconnect sharing a peripheral bus between a host and an AXI to
-- APB bridge does.  A master waits in its access phase, its ready low,
-- until it is granted; the slave then sees the transfer's setup phase,
-- then its access phase.  Grants alternate when both masters wait.
entity apb_share is
  generic(
    config_c : nsl_amba.apb.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    host_i : in nsl_amba.apb.master_t;
    host_o : out nsl_amba.apb.slave_t;
    bridge_i : in nsl_amba.apb.master_t;
    bridge_o : out nsl_amba.apb.slave_t;

    slave_o : out nsl_amba.apb.master_t;
    slave_i : in nsl_amba.apb.slave_t
    );
end entity;

architecture beh of apb_share is

  type grant_t is (GRANT_NONE, GRANT_HOST, GRANT_BRIDGE);

  type regs_t is
  record
    grant: grant_t;
    -- First cycle of a grant: the slave sees the setup phase
    setup: boolean;
    last: grant_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.grant <= GRANT_NONE;
      r.last <= GRANT_BRIDGE;
    end if;
  end process;

  transition: process(r, host_i, bridge_i, slave_i) is
    variable granted : nsl_amba.apb.master_t;
  begin
    rin <= r;
    rin.setup <= false;

    case r.grant is
      when GRANT_NONE =>
        if host_i.sel = '1' and (bridge_i.sel = '0' or r.last = GRANT_BRIDGE) then
          rin.grant <= GRANT_HOST;
          rin.setup <= true;
        elsif bridge_i.sel = '1' then
          rin.grant <= GRANT_BRIDGE;
          rin.setup <= true;
        end if;

      when others =>
        if r.grant = GRANT_HOST then
          granted := host_i;
        else
          granted := bridge_i;
        end if;
        if not r.setup and slave_i.ready = '1' then
          rin.last <= r.grant;
          rin.grant <= GRANT_NONE;
        end if;
    end case;
  end process;

  mealy: process(r, host_i, bridge_i, slave_i) is
    variable idle : nsl_amba.apb.slave_t;
  begin
    idle := slave_i;
    idle.ready := '0';
    host_o <= idle;
    bridge_o <= idle;
    slave_o <= nsl_amba.apb.transfer_idle(config_c);

    case r.grant is
      when GRANT_HOST =>
        slave_o <= host_i;
        if r.setup then
          slave_o.enable <= '0';
        else
          host_o <= slave_i;
        end if;

      when GRANT_BRIDGE =>
        slave_o <= bridge_i;
        if r.setup then
          slave_o.enable <= '0';
        else
          bridge_o <= slave_i;
        end if;

      when GRANT_NONE =>
        null;
    end case;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi_m2m_dma.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_simulation.logging.all;

-- The microcoded DMA reaching its own register file: its AXI master
-- reaches the RAM and, through an AXI to APB bridge, its APB slave,
-- which it shares with the host through apb_share.  A register access
-- must never wait on the thread engine, which may itself wait on an
-- APB access queued behind the host's:
--
-- * a channel copies words into its own INTEN register, two stores in
--   a row, while the host reads its CSR and CPC in a loop;
--
-- * a channel writes DBGCMD four times in a row through the bridge,
--   as a program restarting channels does, while the host reads its
--   CSR;
--
-- * a channel loads a channel register of its own controller, then
--   stores it: the load waits on the register read while the thread
--   engine waits on the reader for its next instruction fetch.
--
-- A watchdog fails the bench if either does not complete.
entity tb is
end tb;

architecture arch of tb is

  constant dma_config_c : config_t := config(address_width => 32,
                                             data_bus_width => 32,
                                             id_width => 2,
                                             max_length => 16,
                                             size => true,
                                             burst => true,
                                             cache => true);
  constant xbar_config_c : config_t := config(address_width => 32,
                                              data_bus_width => 32,
                                              id_width => 3,
                                              max_length => 16,
                                              size => true,
                                              burst => true,
                                              cache => true);
  constant apb_config_c : nsl_amba.apb.config_t := nsl_amba.apb.apb3_config(address_width => 32,
                                                                            data_bus_width => 32);
  constant routing_table_c : nsl_amba.address.address_vector
    := nsl_amba.address.routing_table(32, "x0000----/16", "x0001----/16");
  -- The DMA's registers, as its AXI master sees them
  constant regs_base_c : natural := 16#10000#;
  constant timeout_c : natural := 20000;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal cycle_s : natural := 0;

  signal master_bus : bus_vector(0 to 1);
  signal slave_bus : bus_vector(0 to 1);
  signal host_m_s, bridge_m_s, dma_m_s : nsl_amba.apb.master_t;
  signal host_s_s, bridge_s_s, dma_s_s : nsl_amba.apb.slave_t;
  signal irq_s : std_ulogic_vector(3 downto 0);
  signal irq_abort_s : std_ulogic;

  function hex(v : unsigned) return string is
  begin
    return nsl_data.text.to_hex_string(std_ulogic_vector(v));
  end function;

begin

  dma: nsl_amba.axi_m2m_dma.axi_m2m_microcoded_dma
    generic map(
      config_c => dma_config_c,
      apb_config_c => apb_config_c,
      channel_count_c => 2,
      event_count_c => 4,
      peripheral_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_o => master_bus(1).m,
      axi_i => master_bus(1).s,
      apb_i => dma_m_s,
      apb_o => dma_s_s,
      irq_o => irq_s,
      irq_abort_o => irq_abort_s,
      periph_o => open
      );

  xbar: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => dma_config_c,
      slave_config_c => xbar_config_c,
      master_count_c => 2,
      routing_table_c => routing_table_c,
      default_slave_c => -1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      slave_i(0) => master_bus(0).m,
      slave_i(1) => master_bus(1).m,
      slave_o(0) => master_bus(0).s,
      slave_o(1) => master_bus(1).s,
      master_o(0) => slave_bus(0).m,
      master_o(1) => slave_bus(1).m,
      master_i(0) => slave_bus(0).s,
      master_i(1) => slave_bus(1).s
      );

  ram: nsl_amba.ram.axi4_mm_full_ram
    generic map(
      config_c => xbar_config_c,
      byte_size_l2_c => 16
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_i => slave_bus(0).m,
      axi_o => slave_bus(0).s
      );

  bridge: nsl_amba.axi_apb.axi4_apb_bridge
    generic map(
      axi_config_c => xbar_config_c,
      apb_config_c => apb_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      irq_n_o => open,
      axi_i => slave_bus(1).m,
      axi_o => slave_bus(1).s,
      apb_o => bridge_m_s,
      apb_i => bridge_s_s
      );

  share: entity work.apb_share
    generic map(
      config_c => apb_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      host_i => host_m_s,
      host_o => host_s_s,
      bridge_i => bridge_m_s,
      bridge_o => bridge_s_s,
      slave_o => dma_m_s,
      slave_i => dma_s_s
      );

  cycles: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      cycle_s <= cycle_s + 1;
    end if;
  end process;

  watchdog: process is
  begin
    wait until cycle_s = 100000;
    assert done_s(0) = '1'
      report "Register accesses deadlocked"
      severity failure;
    wait;
  end process;

  host: process is
    variable rsp : resp_enum_t;
    variable v : unsigned(31 downto 0);
    variable start : natural;
    variable rdata : byte_string(0 to 7);

    procedure reg_read(offset : natural; value : out unsigned) is
      variable err : boolean;
    begin
      if clock_s = '1' then
        wait until falling_edge(clock_s);
      end if;
      nsl_amba.apb.apb_read(apb_config_c, clock_s, host_s_s, host_m_s,
                            to_unsigned(offset, 32), value, err);
    end procedure;

    procedure reg_write(offset : natural; value : unsigned) is
      variable err : boolean;
    begin
      if clock_s = '1' then
        wait until falling_edge(clock_s);
      end if;
      nsl_amba.apb.apb_write(apb_config_c, clock_s, host_s_s, host_m_s,
                             to_unsigned(offset, 32), value, err => err);
    end procedure;

    procedure mem_write(addr : natural; data : byte_string) is
      alias d : byte_string(0 to data'length-1) is data;
      variable i, chunk : natural;
    begin
      i := 0;
      while i < d'length
      loop
        chunk := 16;
        if chunk > d'length - i then
          chunk := d'length - i;
        end if;
        burst_write(dma_config_c, clock_s, master_bus(0).s, master_bus(0).m,
                    to_unsigned(addr + i, 32), d(i to i + chunk - 1), rsp);
        i := i + chunk;
      end loop;
    end procedure;

    -- Starts channel ch at pc through the debug registers
    procedure start_channel(ch : natural; pc : natural) is
      constant go : byte_string := asm_go(ch, to_unsigned(pc, 32));
    begin
      reg_write(reg_dbginst0_c, unsigned(go(1)) & unsigned(go(0)) & x"0000");
      reg_write(reg_dbginst1_c, unsigned(go(5)) & unsigned(go(4)) & unsigned(go(3)) & unsigned(go(2)));
      reg_write(reg_dbgcmd_c, to_unsigned(0, 32));
      start := cycle_s;
      loop
        reg_read(reg_dbgstatus_c, v);
        exit when v(0) = '0';
        assert cycle_s - start < timeout_c
          report "debug interface stays busy"
          severity failure;
      end loop;
    end procedure;

    -- Reads CSR and CPC of channel ch until it stopped
    procedure poll_until_stopped(ch : natural; what : string) is
    begin
      start := cycle_s;
      loop
        reg_read(reg_csr0_c + 8 * ch, v);
        exit when v(3 downto 0) = "0000";
        reg_read(reg_cpc0_c + 8 * ch, v);
        assert cycle_s - start < timeout_c
          report what & ": channel " & integer'image(ch) & " does not stop"
          severity failure;
      end loop;
    end procedure;

    -- Copies 64 words onto INTEN, two stores in a row
    constant inten_prog_c : byte_string :=
      asm_mov_ccr(ccr_value(src_size_l2 => 2, src_len => 1,
                            dst_size_l2 => 2, dst_len => 1, dst_incr => false))
      & asm_mov_sar(x"00000400")
      & asm_mov_dar(to_unsigned(regs_base_c + reg_inten_c, 32))
      & asm_lp(0, 32)
      & asm_ld & asm_ld & asm_st & asm_st
      & asm_lpend(0, 4)
      & asm_wmb
      & asm_end;

    -- Writes DBGINST0 (a DMASEV 1 to the manager), then DBGCMD four
    -- times in a row: with the writer holding the second write and the
    -- third in its slot, the engine waits to hand the fourth over.
    constant dbgcmd_prog_c : byte_string :=
      asm_mov_ccr(ccr_value(src_size_l2 => 2, src_len => 1,
                            dst_size_l2 => 2, dst_len => 1, dst_incr => false))
      & asm_mov_sar(x"00000500")
      & asm_mov_dar(to_unsigned(regs_base_c + reg_dbginst0_c, 32))
      & asm_ld & asm_st
      & asm_mov_dar(to_unsigned(regs_base_c + reg_dbgcmd_c, 32))
      & asm_ld & asm_ld & asm_ld & asm_ld
      & asm_st & asm_st & asm_st & asm_st
      & asm_wmb
      & asm_end;

    -- Copies CSR0 and CPC0 to RAM through the bridge
    constant self_load_prog_c : byte_string :=
      asm_mov_ccr(ccr_value(src_size_l2 => 2, src_len => 2,
                            dst_size_l2 => 2, dst_len => 2))
      & asm_mov_sar(to_unsigned(regs_base_c + reg_csr0_c, 32))
      & asm_mov_dar(x"00000600")
      & asm_ld & asm_st
      & asm_wmb
      & asm_end;

    constant zeros_c : byte_string(0 to 255) := (others => x"00");
  begin
    done_s(0) <= '0';
    host_m_s <= nsl_amba.apb.transfer_idle(apb_config_c);
    master_bus(0).m.ar <= address_defaults(dma_config_c);
    master_bus(0).m.r <= handshake_defaults(dma_config_c);
    master_bus(0).m.aw <= address_defaults(dma_config_c);
    master_bus(0).m.w <= write_data_defaults(dma_config_c);
    master_bus(0).m.b <= accept(dma_config_c, true);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    mem_write(16#400#, zeros_c);
    -- DBGINST0 of a DMASEV 1 to the manager, then zeros
    mem_write(16#500#, from_hex("00003408") & zeros_c(0 to 15));
    mem_write(16#100#, inten_prog_c);
    mem_write(16#200#, dbgcmd_prog_c);
    mem_write(16#300#, self_load_prog_c);

    log_info("channel stores into its own registers, host reads channel registers");
    start_channel(0, 16#100#);
    poll_until_stopped(0, "self stores");
    reg_read(reg_cpc0_c, v);
    assert v = 16#100# + inten_prog_c'length
      report "channel 0 stopped at 0x" & hex(v)
      severity failure;

    log_info("channel writes DBGCMD four times, host reads channel registers");
    start_channel(1, 16#200#);
    poll_until_stopped(1, "self DBGCMD");

    start := cycle_s;
    loop
      reg_read(reg_dbgstatus_c, v);
      exit when v(0) = '0';
      assert cycle_s - start < timeout_c
        report "debug interface stays busy"
        severity failure;
    end loop;

    log_info("channel loads its own channel registers");
    start_channel(1, 16#300#);
    poll_until_stopped(1, "self load");
    burst_read(dma_config_c, clock_s, master_bus(0).s, master_bus(0).m,
               to_unsigned(16#600#, 32), rdata, rsp);
    assert rdata = from_hex("00000000") & to_le(to_unsigned(16#100# + inten_prog_c'length, 32))
      report "channel 1 copied CSR0, CPC0 as " & nsl_data.text.to_string(rdata)
      severity failure;

    reg_read(reg_int_event_ris_c, v);
    assert v(1) = '1'
      report "DMASEV 1 issued by the channel's DBGCMD writes did not execute, RIS 0x" & hex(v)
      severity failure;

    log_info("done");
    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 32 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end architecture;
