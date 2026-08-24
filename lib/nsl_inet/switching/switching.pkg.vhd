library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_logic, nsl_math;
use nsl_data.bytestream.all;
use nsl_inet.mac.all;

-- Store-and-forward Ethernet switching (802.1D-style transparent
-- bridge) over AXI4-Stream.
--
-- All ports share one clock domain and one data width of 1, 2 or 4
-- bytes. Port-facing streams use keep, last, and a 1-bit user flag
-- that marks a bad frame when set on the last beat. Beats are packed:
-- keep may only deassert a contiguous group of trailing bytes on the
-- last beat.
--
-- Each ingress port stores a complete frame in a cancellable buffer.
-- Bad frames and frames hitting a full buffer are dropped atomically;
-- committed frames are never dropped. The destination address is
-- looked up in a shared MAC table while the frame is being received,
-- and the resulting egress port mask travels as per-frame sideband
-- metadata. Unknown, broadcast and group destinations are flooded to
-- all ports enabled in flood_mask_i except the ingress port. A frame
-- whose destination is located on its own ingress port is dropped.
--
-- The fabric runs one round-robin arbiter per egress port over the
-- ingress head-of-queue frames. Multicast replays the frame from the
-- ingress buffer once per destination port.
--
-- The MAC table either learns source addresses of committed frames
-- (with aging), or serves a static address list passed as generics.
package switching is

  constant max_port_count_c : natural := 16;

  -- Port sets are max-sized; bits at and above the actual port count
  -- are ignored.
  subtype port_mask_t is std_ulogic_vector(0 to max_port_count_c-1);
  subtype port_index_t is natural range 0 to max_port_count_c-1;
  type port_index_vector is array(integer range <>) of port_index_t;

  constant no_static_macs_c : mac48_vector(1 to 0) := (others => ethernet_broadcast_addr_c);
  constant no_static_ports_c : port_index_vector(1 to 0) := (others => 0);

  type config_t is
  record
    -- Stream width, power of two
    byte_count: natural range 1 to 4;
    port_count: natural range 2 to max_port_count_c;
    -- Log2 of per-ingress buffer size, in bytes
    buffer_bytes_l2: natural;
    -- Log2 of MAC table bucket count
    table_entry_count_l2: natural;
    table_way_count: natural range 1 to 4;
    learning_enabled: boolean;
    -- Learned entries expire 2**age_time_l2 clock cycles after their
    -- last refresh. 0 disables aging.
    age_time_l2: natural;
  end record;

  function config(byte_count: natural;
                  port_count: natural;
                  buffer_bytes_l2: natural;
                  table_entry_count_l2: natural := 6;
                  table_way_count: natural := 2;
                  learning_enabled: boolean := true;
                  age_time_l2: natural := 0) return config_t;

  -- Port-facing stream configuration: keep, last, 1-bit user carrying
  -- the bad-frame flag, meaningful on the last beat only. Egress
  -- streams use the same configuration with user always low.
  function port_config(cfg: config_t) return nsl_amba.axi4_stream.config_t;

  -- Stream configuration once the bad-frame flag has been consumed by
  -- the ingress: keep and last only.
  function internal_config(cfg: config_t) return nsl_amba.axi4_stream.config_t;

  -- Frame storage word encoding, sized to fit 9-bit granularity RAMs
  -- at every supported width: 8*byte_count data bits, 1 last bit,
  -- log2(byte_count) bits holding the number of bytes carried by the
  -- beat, minus one. Non-last beats are full, so the count field
  -- reads "bytes carried minus one" on every beat.
  function storage_width(cfg: config_t) return natural;
  function storage_pack(cfg: config_t;
                        m: nsl_amba.axi4_stream.master_t) return std_ulogic_vector;
  -- Returned beat is valid; the caller is expected to gate valid with
  -- the storage handshake.
  function storage_unpack(cfg: config_t;
                          v: std_ulogic_vector) return nsl_amba.axi4_stream.master_t;

  -- I/G bit of an ethernet address
  function is_group(mac: mac48_t) return boolean;

  -- MAC table lookup handshake. Assert valid with a stable address
  -- and hold until the result valid pulse. The table serves querying
  -- ports round-robin; a query is answered in bounded time, well
  -- under a minimum frame duration.
  type lookup_query_t is
  record
    valid: std_ulogic;
    mac: mac48_t;
  end record;

  -- Lookup result. When hit is set, mask is the one-hot mask of the
  -- port the address was last seen on. When hit is clear, mask is
  -- undefined and the requester is expected to flood.
  type lookup_result_t is
  record
    valid: std_ulogic;
    hit: std_ulogic;
    mask: port_mask_t;
  end record;

  -- Learning strobe, asserted for one cycle when a frame commits on
  -- the ingress identified by the vector index. Bad frames must not
  -- be learned from.
  type learn_t is
  record
    valid: std_ulogic;
    mac: mac48_t;
  end record;

  type lookup_query_vector is array(integer range <>) of lookup_query_t;
  type lookup_result_vector is array(integer range <>) of lookup_result_t;
  type learn_vector is array(integer range <>) of learn_t;

  -- Ingress head-of-queue frame announcement. mask holds the set of
  -- egress ports the frame still has to reach; it stays valid, with
  -- bits cleared as copies get delivered, until the set is empty.
  type forward_req_t is
  record
    valid: std_ulogic;
    mask: port_mask_t;
  end record;

  -- Fabric acknowledge. taken pulses the one-hot bit of an egress
  -- port that accepted a complete copy of the frame. The ingress
  -- rewinds its buffer read side for the next copy, or releases the
  -- frame when the pending set becomes empty.
  type forward_ack_t is
  record
    taken: port_mask_t;
  end record;

  type forward_req_vector is array(integer range <>) of forward_req_t;
  type forward_ack_vector is array(integer range <>) of forward_ack_t;

  -- Complete switch: port_count symmetric ports, each a
  -- port_config() stream pair. A management CPU attaches to an
  -- ordinary port; flood_mask_i selects which ports receive flooded
  -- frames, letting the CPU port opt out at run time.
  component switching_bridge is
    generic(
      config_c: config_t;
      static_macs_c: mac48_vector := no_static_macs_c;
      static_ports_c: port_index_vector := no_static_ports_c
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      flood_mask_i: in port_mask_t := (others => '1');

      in_i: in nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
      in_o: out nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1);

      out_o: out nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
      out_i: in nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1)
      );
  end component;

  -- Per-port ingress: cancellable frame buffer, destination lookup,
  -- source learning, per-frame egress mask computation. in_* is a
  -- port_config() stream, frame_* an internal_config() one.
  --
  -- The input stream is never backpressured in operation; in_o.ready
  -- only stays low for one cycle after reset release, so upstream
  -- must not present a beat on the very first cycle out of reset.
  component switching_ingress is
    generic(
      config_c: config_t;
      port_index_c: port_index_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      flood_mask_i: in port_mask_t;

      in_i: in nsl_amba.axi4_stream.master_t;
      in_o: out nsl_amba.axi4_stream.slave_t;

      lookup_query_o: out lookup_query_t;
      lookup_result_i: in lookup_result_t;
      learn_o: out learn_t;

      frame_o: out nsl_amba.axi4_stream.master_t;
      frame_i: in nsl_amba.axi4_stream.slave_t;
      forward_o: out forward_req_t;
      forward_i: in forward_ack_t
      );
  end component;

  -- Shared MAC address table. Either learns from the per-port learn
  -- strobes, or, when learning is disabled, serves the static table
  -- passed as generics. static_macs_c and static_ports_c pair up by
  -- index.
  component switching_mac_table is
    generic(
      config_c: config_t;
      static_macs_c: mac48_vector := no_static_macs_c;
      static_ports_c: port_index_vector := no_static_ports_c
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      query_i: in lookup_query_vector(0 to config_c.port_count-1);
      result_o: out lookup_result_vector(0 to config_c.port_count-1);

      learn_i: in learn_vector(0 to config_c.port_count-1)
      );
  end component;

  -- Egress side: one round-robin arbiter per egress port over the
  -- ingress frames whose pending mask includes it. frame_* streams
  -- use internal_config(), out_* streams port_config() with user
  -- tied low.
  component switching_fabric is
    generic(
      config_c: config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      frame_i: in nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
      frame_o: out nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1);
      forward_i: in forward_req_vector(0 to config_c.port_count-1);
      forward_o: out forward_ack_vector(0 to config_c.port_count-1);

      out_o: out nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
      out_i: in nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1)
      );
  end component;

end package switching;

package body switching is

  function config(byte_count: natural;
                  port_count: natural;
                  buffer_bytes_l2: natural;
                  table_entry_count_l2: natural := 6;
                  table_way_count: natural := 2;
                  learning_enabled: boolean := true;
                  age_time_l2: natural := 0) return config_t is
  begin
    assert byte_count = 1 or byte_count = 2 or byte_count = 4
      report "Switch stream width must be 1, 2 or 4 bytes"
      severity failure;
    assert 2 ** buffer_bytes_l2 >= 2048
      report "Ingress buffer cannot hold a maximum-size frame"
      severity failure;

    return config_t'(
      byte_count => byte_count,
      port_count => port_count,
      buffer_bytes_l2 => buffer_bytes_l2,
      table_entry_count_l2 => table_entry_count_l2,
      table_way_count => table_way_count,
      learning_enabled => learning_enabled,
      age_time_l2 => age_time_l2
      );
  end function;

  function port_config(cfg: config_t) return nsl_amba.axi4_stream.config_t is
  begin
    return nsl_amba.axi4_stream.config(bytes => cfg.byte_count,
                                       user => 1,
                                       keep => true,
                                       last => true);
  end function;

  function internal_config(cfg: config_t) return nsl_amba.axi4_stream.config_t is
  begin
    return nsl_amba.axi4_stream.config(bytes => cfg.byte_count,
                                       keep => true,
                                       last => true);
  end function;

  function count_width(cfg: config_t) return natural is
  begin
    return nsl_math.arith.log2(cfg.byte_count);
  end function;

  function storage_width(cfg: config_t) return natural is
  begin
    return cfg.byte_count * 8 + 1 + count_width(cfg);
  end function;

  function storage_pack(cfg: config_t;
                        m: nsl_amba.axi4_stream.master_t) return std_ulogic_vector is
    constant s_cfg : nsl_amba.axi4_stream.config_t := internal_config(cfg);
    constant cw : natural := count_width(cfg);
    variable ret : std_ulogic_vector(0 to storage_width(cfg)-1);
    variable count : natural range 0 to cfg.byte_count-1;
  begin
    for i in 0 to cfg.byte_count-1
    loop
      ret(i*8 to i*8+7) := m.data(i);
    end loop;

    count := cfg.byte_count - 1;
    if nsl_amba.axi4_stream.is_last(s_cfg, m) then
      ret(cfg.byte_count*8) := '1';
      count := nsl_amba.axi4_stream.byte_count(s_cfg, m) - 1;
    else
      ret(cfg.byte_count*8) := '0';
    end if;

    if cw /= 0 then
      ret(cfg.byte_count*8+1 to cfg.byte_count*8+cw)
        := std_ulogic_vector(to_unsigned(count, cw));
    end if;

    return ret;
  end function;

  function storage_unpack(cfg: config_t;
                          v: std_ulogic_vector) return nsl_amba.axi4_stream.master_t is
    constant s_cfg : nsl_amba.axi4_stream.config_t := internal_config(cfg);
    constant cw : natural := count_width(cfg);
    alias xv : std_ulogic_vector(0 to v'length-1) is v;
    variable data : byte_string(0 to cfg.byte_count-1);
    variable k : std_ulogic_vector(0 to cfg.byte_count-1);
    variable count : natural range 0 to cfg.byte_count-1;
  begin
    assert v'length = storage_width(cfg)
      report "Storage word width mismatch"
      severity failure;

    for i in 0 to cfg.byte_count-1
    loop
      data(i) := xv(i*8 to i*8+7);
    end loop;

    count := cfg.byte_count - 1;
    if cw /= 0 then
      count := to_integer(unsigned(xv(cfg.byte_count*8+1 to cfg.byte_count*8+cw)));
    end if;

    k := (others => '0');
    for i in k'range
    loop
      if i <= count then
        k(i) := '1';
      end if;
    end loop;

    return nsl_amba.axi4_stream.transfer(s_cfg,
                                         bytes => data,
                                         keep => k,
                                         last => xv(cfg.byte_count*8) = '1');
  end function;

  function is_group(mac: mac48_t) return boolean is
  begin
    return mac(0)(0) = '1';
  end function;

end package body switching;
