library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_amba.axi_m2m_dma_priv.all;

-- Peripheral request interfaces of axi_m2m_microcoded_dma.
--
-- Each interface has a request FIFO of request_depth_c entries (the
-- DMA-330's request acceptance capability): drready is low while it
-- is full, except while flushing where every incoming request is
-- taken and discarded until the flush acknowledge.
--
-- Acknowledges come from three sources (thread engine flushes, reader
-- DMALDP completions, writer DMASTP completions).  One source is
-- granted at a time, once the acknowledge output register of its
-- peripheral is free.  The grant is registered: it is set the cycle
-- after the source request is seen, the source takes it as accepted
-- on that cycle.
entity axi_m2m_dma_peripheral is
  generic(
    peripheral_count_c : positive;
    request_depth_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    periph_i : in peripheral_vector(0 to peripheral_count_c-1);
    periph_o : out dmac_vector(0 to peripheral_count_c-1);

    request_o : out request_state_vector(0 to peripheral_count_c-1);
    pop_i : in std_ulogic_vector(0 to peripheral_count_c-1);

    flush_i : in ack_request_t;
    flush_grant_o : out std_ulogic;
    read_ack_i : in ack_request_t;
    read_grant_o : out std_ulogic;
    write_ack_i : in ack_request_t;
    write_grant_o : out std_ulogic
    );
end entity;

architecture beh of axi_m2m_dma_peripheral is

  type grant_t is (
    GRANT_NONE,
    GRANT_FLUSH,
    GRANT_READ,
    GRANT_WRITE
    );

  type ack_t is
  record
    valid: std_ulogic;
    atype: request_type_t;
  end record;
  type ack_vector is array (natural range <>) of ack_t;

  -- Request FIFO of a peripheral, head first
  type fifo_t is
  record
    count: natural range 0 to request_depth_c;
    entry: request_state_vector(0 to request_depth_c-1);
  end record;
  type fifo_vector is array (natural range <>) of fifo_t;

  type regs_t is
  record
    fifo: fifo_vector(0 to peripheral_count_c-1);
    flushing: std_ulogic_vector(0 to peripheral_count_c-1);
    ack: ack_vector(0 to peripheral_count_c-1);
    grant: grant_t;
  end record;

  signal r, rin: regs_t;

  function ack_free(r : regs_t; periph : periph_t) return boolean
  is
  begin
    for p in 0 to peripheral_count_c-1
    loop
      if periph = to_unsigned(p, periph'length) then
        return r.ack(p).valid = '0';
      end if;
    end loop;
    return false;
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      for p in 0 to peripheral_count_c-1
      loop
        r.fifo(p).count <= 0;
        r.ack(p).valid <= '0';
      end loop;
      r.flushing <= (others => '0');
      r.grant <= GRANT_NONE;
    end if;
  end process;

  transition: process(r, periph_i, pop_i, flush_i, read_ack_i, write_ack_i) is
    variable f : fifo_t;
  begin
    rin <= r;

    for p in 0 to peripheral_count_c-1
    loop
      f := r.fifo(p);

      if pop_i(p) = '1' and f.count /= 0 then
        for i in 0 to request_depth_c-2
        loop
          f.entry(i) := f.entry(i+1);
        end loop;
        f.count := f.count - 1;
      end if;

      if r.ack(p).valid = '1' and periph_i(p).daready = '1' then
        rin.ack(p).valid <= '0';
      end if;

      if periph_i(p).drvalid = '1' then
        if r.flushing(p) = '1' then
          if periph_i(p).drtype = drtype_flush_c then
            rin.flushing(p) <= '0';
          end if;
        elsif r.fifo(p).count /= request_depth_c then
          if periph_i(p).drtype = drtype_single_c
            or periph_i(p).drtype = drtype_burst_c then
            f.entry(f.count).valid := '1';
            f.entry(f.count).burst := periph_i(p).drtype(0);
            f.entry(f.count).last := periph_i(p).drlast;
            f.count := f.count + 1;
          end if;
        end if;
      end if;

      rin.fifo(p) <= f;
    end loop;

    case r.grant is
      when GRANT_NONE =>
        if flush_i.valid = '1' and ack_free(r, flush_i.periph) then
          rin.grant <= GRANT_FLUSH;
        elsif write_ack_i.valid = '1' and ack_free(r, write_ack_i.periph) then
          rin.grant <= GRANT_WRITE;
        elsif read_ack_i.valid = '1' and ack_free(r, read_ack_i.periph) then
          rin.grant <= GRANT_READ;
        end if;

      when GRANT_FLUSH =>
        rin.grant <= GRANT_NONE;
        for p in 0 to peripheral_count_c-1
        loop
          if flush_i.periph = to_unsigned(p, periph_t'length) then
            rin.ack(p).valid <= '1';
            rin.ack(p).atype <= datype_flush_c;
            rin.fifo(p).count <= 0;
            rin.flushing(p) <= '1';
          end if;
        end loop;

      when GRANT_WRITE =>
        rin.grant <= GRANT_NONE;
        for p in 0 to peripheral_count_c-1
        loop
          if write_ack_i.periph = to_unsigned(p, periph_t'length) then
            rin.ack(p).valid <= '1';
            rin.ack(p).atype <= write_ack_i.atype;
          end if;
        end loop;

      when GRANT_READ =>
        rin.grant <= GRANT_NONE;
        for p in 0 to peripheral_count_c-1
        loop
          if read_ack_i.periph = to_unsigned(p, periph_t'length) then
            rin.ack(p).valid <= '1';
            rin.ack(p).atype <= read_ack_i.atype;
          end if;
        end loop;
    end case;
  end process;

  moore: process(r) is
  begin
    for p in 0 to peripheral_count_c-1
    loop
      periph_o(p).drready <= '1';
      if r.flushing(p) = '0' and r.fifo(p).count = request_depth_c then
        periph_o(p).drready <= '0';
      end if;
      periph_o(p).davalid <= r.ack(p).valid;
      periph_o(p).datype <= r.ack(p).atype;
      request_o(p).valid <= '0';
      if r.fifo(p).count /= 0 and r.flushing(p) = '0' then
        request_o(p).valid <= '1';
      end if;
      request_o(p).burst <= r.fifo(p).entry(0).burst;
      request_o(p).last <= r.fifo(p).entry(0).last;
    end loop;

    flush_grant_o <= '0';
    read_grant_o <= '0';
    write_grant_o <= '0';
    case r.grant is
      when GRANT_NONE => null;
      when GRANT_FLUSH => flush_grant_o <= '1';
      when GRANT_READ => read_grant_o <= '1';
      when GRANT_WRITE => write_grant_o <= '1';
    end case;
  end process;

end architecture;
