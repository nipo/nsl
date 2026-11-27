library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

-- Agilex 5 hard processor system (HPS) seen from the fabric.
package hps is

  -- Bridges are AXI4 (ACE5-Lite for f2h).  They map to NSL records
  -- field by field: AxLEN is 8 bits wide, AxLOCK is a single bit
  -- (normal or exclusive).

  -- h2f (HPS is master, fabric is slave).  Data width is 32, 64 or
  -- 128 bits, the wrapper sets the bridge width from the configuration
  -- (no software setting is involved).  Address width is 38 or less,
  -- from 20, and sets the size of the bridge window.  QoS, region and
  -- user are not driven by the HPS.
  constant h2f_native_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 38, data_bus_width => 128,
                               id_width => 4, max_length => 256, size => true, burst => true,
                               cache => true, lock => true);

  -- lwh2f (HPS is master, fabric is slave), lightweight bridge.  Data
  -- width is 32 bits, address width is 29 or less, from 20.
  constant lwh2f_native_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 29, data_bus_width => 32,
                               id_width => 4, max_length => 256, size => true, burst => true,
                               cache => true, lock => true);

  -- f2h (fabric is master, HPS is slave), ACE5-Lite into the cache
  -- coherency unit, through the MPFE.  Data width is 256 bits,
  -- address width is 40 or less, from 20.  user maps to AxUSER, WUSER,
  -- BUSER and RUSER.  ACE5-Lite domain and snoop fields come from
  -- f2h_ace_c (see hps_f2h_ace_t), barrier, atomic and stash fields
  -- are tied to zero.  The SMMU stream ID is tied as the vendor IP
  -- does without SMMU.
  constant f2h_native_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 40, data_bus_width => 256,
                               user_width => 8, id_width => 5, max_length => 256,
                               size => true, region => true, qos => true,
                               cache => true, burst => true, lock => true);

  -- f2sdram (fabric is master, HPS memory is slave), AXI4 through the
  -- MPFE to the HPS EMIF.  Data width is 64, 128 or 256 bits, address
  -- width is 40 or less, from 20.  user maps to AxUSER[7:0], WUSER,
  -- BUSER and RUSER.  The SMMU stream ID part of AxUSER is tied as the
  -- vendor IP does without SMMU.
  constant f2sdram_native_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 40, data_bus_width => 256,
                               user_width => 8, id_width => 5, max_length => 256,
                               size => true, region => true, qos => true,
                               cache => true, burst => true, lock => true);

  -- An h2f port without slave: never accepts anything.
  constant h2f_slave_idle_c : nsl_amba.axi4_mm.slave_t := (
    aw => nsl_amba.axi4_mm.handshake_defaults(h2f_native_config_c),
    w => nsl_amba.axi4_mm.handshake_defaults(h2f_native_config_c),
    b => nsl_amba.axi4_mm.write_response_defaults(h2f_native_config_c),
    ar => nsl_amba.axi4_mm.handshake_defaults(h2f_native_config_c),
    r => nsl_amba.axi4_mm.read_data_defaults(h2f_native_config_c)
    );

  -- An lwh2f port without slave: never accepts anything.
  constant lwh2f_slave_idle_c : nsl_amba.axi4_mm.slave_t := (
    aw => nsl_amba.axi4_mm.handshake_defaults(lwh2f_native_config_c),
    w => nsl_amba.axi4_mm.handshake_defaults(lwh2f_native_config_c),
    b => nsl_amba.axi4_mm.write_response_defaults(lwh2f_native_config_c),
    ar => nsl_amba.axi4_mm.handshake_defaults(lwh2f_native_config_c),
    r => nsl_amba.axi4_mm.read_data_defaults(lwh2f_native_config_c)
    );

  -- An f2h port without master: never issues anything.
  constant f2h_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(f2h_native_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(f2h_native_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(f2h_native_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(f2h_native_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(f2h_native_config_c)
    );

  -- An f2sdram port without master: never issues anything.
  constant f2sdram_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(f2sdram_native_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(f2sdram_native_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(f2sdram_native_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(f2sdram_native_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(f2sdram_native_config_c)
    );

  -- ACE5-Lite fields of f2h transactions, constant for the port.
  -- With both domains "00" (non-shareable) and both snoops "0000",
  -- reads are ReadNoSnoop and writes WriteNoSnoop: no coherency.
  -- Domains "01" or "10" with zero snoops make ReadOnce and
  -- WriteUnique, coherent with the CPU caches.
  type hps_f2h_ace_t is
  record
    ar_domain : std_ulogic_vector(1 downto 0);
    ar_snoop : std_ulogic_vector(3 downto 0);
    aw_domain : std_ulogic_vector(1 downto 0);
    aw_snoop : std_ulogic_vector(3 downto 0);
  end record;

  constant hps_f2h_non_coherent_c : hps_f2h_ace_t := (
    ar_domain => "00", ar_snoop => "0000",
    aw_domain => "00", aw_snoop => "0000");

  -- MPFE to HPS EMIF link (io96b0_to_hps in vendor IP), MPFE side.
  -- Fields are the ports of the EMIF IP, axi4 is the s0_axi4 port,
  -- axi4_1 the s1_axi4 one, second channel of a two-channel topology
  -- (2x16, unused otherwise), axil is the s0_noc_axi4lite one.  Link is a direct connection
  -- between the hard blocks, clocks and resets come from the EMIF.
  type hps_emif_o_t is
  record
    axi4_awid : std_ulogic_vector(6 downto 0);
    axi4_awaddr : std_ulogic_vector(39 downto 0);
    axi4_awlen : std_ulogic_vector(7 downto 0);
    axi4_awsize : std_ulogic_vector(2 downto 0);
    axi4_awburst : std_ulogic_vector(1 downto 0);
    axi4_awlock : std_ulogic;
    axi4_awqos : std_ulogic_vector(3 downto 0);
    axi4_awuser : std_ulogic_vector(13 downto 0);
    axi4_awvalid : std_ulogic;
    axi4_wdata : std_ulogic_vector(255 downto 0);
    axi4_wstrb : std_ulogic_vector(31 downto 0);
    axi4_wlast : std_ulogic;
    axi4_wuser : std_ulogic_vector(31 downto 0);
    axi4_wvalid : std_ulogic;
    axi4_bready : std_ulogic;
    axi4_arid : std_ulogic_vector(6 downto 0);
    axi4_araddr : std_ulogic_vector(39 downto 0);
    axi4_arlen : std_ulogic_vector(7 downto 0);
    axi4_arsize : std_ulogic_vector(2 downto 0);
    axi4_arburst : std_ulogic_vector(1 downto 0);
    axi4_arlock : std_ulogic;
    axi4_arqos : std_ulogic_vector(3 downto 0);
    axi4_aruser : std_ulogic_vector(13 downto 0);
    axi4_arvalid : std_ulogic;
    axi4_rready : std_ulogic;
    axi4_1_awid : std_ulogic_vector(6 downto 0);
    axi4_1_awaddr : std_ulogic_vector(39 downto 0);
    axi4_1_awlen : std_ulogic_vector(7 downto 0);
    axi4_1_awsize : std_ulogic_vector(2 downto 0);
    axi4_1_awburst : std_ulogic_vector(1 downto 0);
    axi4_1_awlock : std_ulogic;
    axi4_1_awqos : std_ulogic_vector(3 downto 0);
    axi4_1_awuser : std_ulogic_vector(13 downto 0);
    axi4_1_awvalid : std_ulogic;
    axi4_1_wdata : std_ulogic_vector(255 downto 0);
    axi4_1_wstrb : std_ulogic_vector(31 downto 0);
    axi4_1_wlast : std_ulogic;
    axi4_1_wuser : std_ulogic_vector(31 downto 0);
    axi4_1_wvalid : std_ulogic;
    axi4_1_bready : std_ulogic;
    axi4_1_arid : std_ulogic_vector(6 downto 0);
    axi4_1_araddr : std_ulogic_vector(39 downto 0);
    axi4_1_arlen : std_ulogic_vector(7 downto 0);
    axi4_1_arsize : std_ulogic_vector(2 downto 0);
    axi4_1_arburst : std_ulogic_vector(1 downto 0);
    axi4_1_arlock : std_ulogic;
    axi4_1_arqos : std_ulogic_vector(3 downto 0);
    axi4_1_aruser : std_ulogic_vector(13 downto 0);
    axi4_1_arvalid : std_ulogic;
    axi4_1_rready : std_ulogic;
    axil_awaddr : std_ulogic_vector(26 downto 0);
    axil_awvalid : std_ulogic;
    axil_wdata : std_ulogic_vector(31 downto 0);
    axil_wstrb : std_ulogic_vector(3 downto 0);
    axil_wvalid : std_ulogic;
    axil_bready : std_ulogic;
    axil_araddr : std_ulogic_vector(26 downto 0);
    axil_arvalid : std_ulogic;
    axil_rready : std_ulogic;
  end record;

  -- MPFE to HPS EMIF link, EMIF side.  axi4_clock is noc_aclk_0,
  -- axi4_1_clock noc_aclk_1, axil_clock is s0_noc_axi4lite_clock.
  type hps_emif_i_t is
  record
    axi4_clock : std_ulogic;
    axi4_awready : std_ulogic;
    axi4_wready : std_ulogic;
    axi4_bid : std_ulogic_vector(6 downto 0);
    axi4_bresp : std_ulogic_vector(1 downto 0);
    axi4_bvalid : std_ulogic;
    axi4_arready : std_ulogic;
    axi4_rid : std_ulogic_vector(6 downto 0);
    axi4_rdata : std_ulogic_vector(255 downto 0);
    axi4_rresp : std_ulogic_vector(1 downto 0);
    axi4_rlast : std_ulogic;
    axi4_ruser : std_ulogic_vector(31 downto 0);
    axi4_rvalid : std_ulogic;
    axi4_1_clock : std_ulogic;
    axi4_1_awready : std_ulogic;
    axi4_1_wready : std_ulogic;
    axi4_1_bid : std_ulogic_vector(6 downto 0);
    axi4_1_bresp : std_ulogic_vector(1 downto 0);
    axi4_1_bvalid : std_ulogic;
    axi4_1_arready : std_ulogic;
    axi4_1_rid : std_ulogic_vector(6 downto 0);
    axi4_1_rdata : std_ulogic_vector(255 downto 0);
    axi4_1_rresp : std_ulogic_vector(1 downto 0);
    axi4_1_rlast : std_ulogic;
    axi4_1_ruser : std_ulogic_vector(31 downto 0);
    axi4_1_rvalid : std_ulogic;
    axil_clock : std_ulogic;
    axil_awready : std_ulogic;
    axil_wready : std_ulogic;
    axil_bresp : std_ulogic_vector(1 downto 0);
    axil_bvalid : std_ulogic;
    axil_arready : std_ulogic;
    axil_rdata : std_ulogic_vector(31 downto 0);
    axil_rresp : std_ulogic_vector(1 downto 0);
    axil_rvalid : std_ulogic;
  end record;

  constant hps_emif_i_idle_c : hps_emif_i_t := (
    axi4_bid => (others => '0'),
    axi4_bresp => (others => '0'),
    axi4_rid => (others => '0'),
    axi4_rdata => (others => '0'),
    axi4_rresp => (others => '0'),
    axi4_ruser => (others => '0'),
    axi4_1_bid => (others => '0'),
    axi4_1_bresp => (others => '0'),
    axi4_1_rid => (others => '0'),
    axi4_1_rdata => (others => '0'),
    axi4_1_rresp => (others => '0'),
    axi4_1_ruser => (others => '0'),
    axil_bresp => (others => '0'),
    axil_rdata => (others => '0'),
    axil_rresp => (others => '0'),
    others => '0');

  -- Plain instantiation of the Agilex 5 HPS atoms, without Platform
  -- Designer.  Only available for Agilex 5 parts (target_part A5E*),
  -- there is no simulation model.
  --
  -- The HPS itself is described by a configuration file of the project
  -- (file type nsl-agilex5-hps), see the nsl_altera.hps documentation.
  -- From it, the build generates the atom layer the wrapper
  -- instantiates (hps_atoms) and the HPS_ISW_DATA assignment holding
  -- the HPS boot configuration.  Generics must agree with the file,
  -- elaboration fails otherwise.
  --
  -- HPS IO pin n (0 to 23 are HPS_IOA_1 to HPS_IOA_24, 24 to 47 are
  -- HPS_IOB_1 to HPS_IOB_24) is hps_io_i(n) for an input pin,
  -- hps_io_o(n) for an output pin, hps_io_io(n) for a bidirectional,
  -- open drain or I2C one, as the file gives its mode.  It must reach a
  -- top level port of the same direction, located on the matching
  -- package ball in the project: Quartus adds fabric buffers on a top
  -- level inout port, which output-only HPS pins cannot take.
  -- hps_io_o elements of other pins are driven '0'.
  --
  -- *_used_c: whether a bridge is connected.  An unused bridge is not
  -- configured in the HPS, its ports are idle.
  --
  -- *_config_c: configuration of each bridge record, defaulting to the
  -- native one.  Elaboration fails unless conversion from/to native is
  -- trivial:
  -- * data width is one the bridge supports (see *_native_config_c);
  -- * address width is in the range the bridge supports.  It sets the
  --   bridge window size of h2f and lwh2f, it is zero-extended
  --   towards the HPS on f2h and f2sdram;
  -- * on h2f and lwh2f, ID width and max_length may be larger than
  --   native (IDs are zero-extended), size and burst are mandatory;
  -- * on f2h and f2sdram, ID width, user width and max_length may be
  --   smaller than native (zero-extended);
  -- * cache, qos, region and lock may be absent.
  --
  -- *_clock_i: clock of the matching bridge, the bridge records are
  -- synchronous to it.  *_reset_n_o is the HPS reset, asserted
  -- asynchronously and released synchronously to the bridge clock.
  -- Each bridge goes through a register stage in each direction at
  -- the core/periphery boundary, and through a skid buffer, as the
  -- vendor IP does.
  --
  -- f2h_ace_c: ACE5-Lite domain and snoop of f2h transactions.
  --
  -- emif_*: link between the MPFE and a Quartus generated HPS EMIF
  -- (emif_io96b_hps).  The HPS only gets memory if emif_used_c.
  --
  -- reset_n_o: HPS reset to the fabric (h2f_reset, inverted), not
  -- synchronized.  user_clock_o: HPS clock manager user clocks 0 and 1.
  --
  -- warm_reset_request_o/warm_reset_ack_i: HPS warm reset handshake.
  -- The HPS requests and waits for the fabric to acknowledge.  Without
  -- warm_reset_handshake_c, the wrapper acknowledges by itself and
  -- warm_reset_ack_i is ignored.
  --
  -- irq_i(n): fabric to HPS interrupt n.
  --
  -- gp_i/gp_o: system manager general purpose registers.
  component hps_wrapper is
    generic(
      h2f_used_c : boolean := false;
      h2f_config_c : nsl_amba.axi4_mm.config_t := h2f_native_config_c;
      lwh2f_used_c : boolean := false;
      lwh2f_config_c : nsl_amba.axi4_mm.config_t := lwh2f_native_config_c;
      f2h_used_c : boolean := false;
      f2h_config_c : nsl_amba.axi4_mm.config_t := f2h_native_config_c;
      f2h_ace_c : hps_f2h_ace_t := hps_f2h_non_coherent_c;
      f2sdram_used_c : boolean := false;
      f2sdram_config_c : nsl_amba.axi4_mm.config_t := f2sdram_native_config_c;
      emif_used_c : boolean := false;

      warm_reset_handshake_c : boolean := false
      );
    port(
      hps_io_i : in std_ulogic_vector(0 to 47) := (others => '0');
      hps_io_o : out std_ulogic_vector(0 to 47);
      hps_io_io : inout std_logic_vector(0 to 47);

      reset_n_o : out std_ulogic;
      user_clock_o : out std_ulogic_vector(0 to 1);
      warm_reset_request_o : out std_ulogic;
      warm_reset_ack_i : in std_ulogic := '0';

      h2f_clock_i : in std_ulogic := '0';
      h2f_reset_n_o : out std_ulogic;
      h2f_o : out nsl_amba.axi4_mm.master_t;
      h2f_i : in nsl_amba.axi4_mm.slave_t := h2f_slave_idle_c;

      lwh2f_clock_i : in std_ulogic := '0';
      lwh2f_reset_n_o : out std_ulogic;
      lwh2f_o : out nsl_amba.axi4_mm.master_t;
      lwh2f_i : in nsl_amba.axi4_mm.slave_t := lwh2f_slave_idle_c;

      f2h_clock_i : in std_ulogic := '0';
      f2h_reset_n_o : out std_ulogic;
      f2h_i : in nsl_amba.axi4_mm.master_t := f2h_master_idle_c;
      f2h_o : out nsl_amba.axi4_mm.slave_t;

      f2sdram_clock_i : in std_ulogic := '0';
      f2sdram_reset_n_o : out std_ulogic;
      f2sdram_i : in nsl_amba.axi4_mm.master_t := f2sdram_master_idle_c;
      f2sdram_o : out nsl_amba.axi4_mm.slave_t;

      emif_o : out hps_emif_o_t;
      emif_i : in hps_emif_i_t := hps_emif_i_idle_c;

      irq_i : in std_ulogic_vector(0 to 63) := (others => '0');
      gp_i : in std_ulogic_vector(31 downto 0) := (others => '0');
      gp_o : out std_ulogic_vector(31 downto 0)
      );
  end component;

  -- Atom side of a bridge where the HPS is master (h2f, lwh2f), at
  -- the widest bridge sizes, signals the HPS drives.  Wrapper
  -- internals.
  type hps_master_fwd_t is
  record
    awid : std_ulogic_vector(3 downto 0);
    awaddr : std_ulogic_vector(39 downto 0);
    awlen : std_ulogic_vector(7 downto 0);
    awsize : std_ulogic_vector(2 downto 0);
    awburst : std_ulogic_vector(1 downto 0);
    awlock : std_ulogic;
    awcache : std_ulogic_vector(3 downto 0);
    awprot : std_ulogic_vector(2 downto 0);
    awvalid : std_ulogic;
    wdata : std_ulogic_vector(127 downto 0);
    wstrb : std_ulogic_vector(15 downto 0);
    wlast : std_ulogic;
    wvalid : std_ulogic;
    bready : std_ulogic;
    arid : std_ulogic_vector(3 downto 0);
    araddr : std_ulogic_vector(39 downto 0);
    arlen : std_ulogic_vector(7 downto 0);
    arsize : std_ulogic_vector(2 downto 0);
    arburst : std_ulogic_vector(1 downto 0);
    arlock : std_ulogic;
    arcache : std_ulogic_vector(3 downto 0);
    arprot : std_ulogic_vector(2 downto 0);
    arvalid : std_ulogic;
    rready : std_ulogic;
  end record;

  -- Atom side of a bridge where the HPS is master, signals towards the
  -- HPS.  Wrapper internals.
  type hps_master_bwd_t is
  record
    awready : std_ulogic;
    wready : std_ulogic;
    bid : std_ulogic_vector(3 downto 0);
    bresp : std_ulogic_vector(1 downto 0);
    bvalid : std_ulogic;
    arready : std_ulogic;
    rid : std_ulogic_vector(3 downto 0);
    rdata : std_ulogic_vector(127 downto 0);
    rresp : std_ulogic_vector(1 downto 0);
    rlast : std_ulogic;
    rvalid : std_ulogic;
  end record;

  -- Atom side of a bridge where the HPS is slave (f2h, f2sdram), at
  -- the widest bridge sizes, signals towards the MPFE.  Wrapper
  -- internals.
  type hps_slave_fwd_t is
  record
    awid : std_ulogic_vector(4 downto 0);
    awaddr : std_ulogic_vector(39 downto 0);
    awlen : std_ulogic_vector(7 downto 0);
    awsize : std_ulogic_vector(2 downto 0);
    awburst : std_ulogic_vector(1 downto 0);
    awlock : std_ulogic;
    awcache : std_ulogic_vector(3 downto 0);
    awprot : std_ulogic_vector(2 downto 0);
    awqos : std_ulogic_vector(3 downto 0);
    awregion : std_ulogic_vector(3 downto 0);
    awuser : std_ulogic_vector(7 downto 0);
    awvalid : std_ulogic;
    wdata : std_ulogic_vector(255 downto 0);
    wstrb : std_ulogic_vector(31 downto 0);
    wlast : std_ulogic;
    wuser : std_ulogic_vector(7 downto 0);
    wvalid : std_ulogic;
    bready : std_ulogic;
    arid : std_ulogic_vector(4 downto 0);
    araddr : std_ulogic_vector(39 downto 0);
    arlen : std_ulogic_vector(7 downto 0);
    arsize : std_ulogic_vector(2 downto 0);
    arburst : std_ulogic_vector(1 downto 0);
    arlock : std_ulogic;
    arcache : std_ulogic_vector(3 downto 0);
    arprot : std_ulogic_vector(2 downto 0);
    arqos : std_ulogic_vector(3 downto 0);
    arregion : std_ulogic_vector(3 downto 0);
    aruser : std_ulogic_vector(7 downto 0);
    arvalid : std_ulogic;
    rready : std_ulogic;
  end record;

  -- Atom side of a bridge where the HPS is slave, signals the MPFE
  -- drives.  Wrapper internals.
  type hps_slave_bwd_t is
  record
    awready : std_ulogic;
    wready : std_ulogic;
    bid : std_ulogic_vector(4 downto 0);
    bresp : std_ulogic_vector(1 downto 0);
    buser : std_ulogic_vector(7 downto 0);
    bvalid : std_ulogic;
    arready : std_ulogic;
    rid : std_ulogic_vector(4 downto 0);
    rdata : std_ulogic_vector(255 downto 0);
    rresp : std_ulogic_vector(1 downto 0);
    rlast : std_ulogic;
    ruser : std_ulogic_vector(7 downto 0);
    rvalid : std_ulogic;
  end record;

  -- Bridge where the HPS is master, from atom signals to an NSL
  -- record of configuration config_c, through the boundary registers
  -- and skid buffers.  reset_n_i resets the skid buffers.
  component hps_master_bridge is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      ps_i : in hps_master_fwd_t;
      ps_o : out hps_master_bwd_t;

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t
      );
  end component;

  -- Bridge where the HPS is slave, from an NSL record of configuration
  -- config_c to atom signals, through the boundary registers and skid
  -- buffers.  reset_n_i resets the skid buffers.
  component hps_slave_bridge is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t;

      ps_o : out hps_slave_fwd_t;
      ps_i : in hps_slave_bwd_t
      );
  end component;

  -- A bridge where the HPS is master (h2f, lwh2f), as exported by the
  -- intel_agilex_5_soc Platform Designer component, seen as NSL records
  -- of configuration config_c, for designs that keep the HPS in a
  -- Platform Designer system rather than using hps_wrapper.  Flat ports
  -- are named as the AXI signals of the exported interface; their
  -- width follows config_c, AxLEN is 8 bits.  ID, size, burst, lock,
  -- cache and prot must be in config_c for them to be passed.
  --
  -- The bridge drives garbage on its valid signals while the fabric
  -- initializes: in particular, the lightweight bridge pulses ARVALID
  -- for one cycle at bring-up, without ever expecting a handshake.  A
  -- slave answering it shifts every later response by one transaction,
  -- then the orphaned response wedges the bridge.  The port guards
  -- against that:
  --
  -- * reset_n_i is asynchronous.  It must be asserted while the fabric
  --   initializes (ninit_done) and while the HPS resets the bridge
  --   (h2f_reset, which must also be the reset of the bridge interface
  --   in the system);
  -- * reset_n_o is reset_n_i, asserted asynchronously and released
  --   synchronously to clock_i: the slave logic must be reset by it;
  -- * while reset_n_o is asserted, no valid and no ready crosses the
  --   port, in either direction.
  --
  -- The port adds no latency: the Platform Designer component already
  -- has its ready latency adapters.
  component hps_pd_master_port is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      reset_n_o : out std_ulogic;

      awid : in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      awaddr : in std_logic_vector(config_c.address_width-1 downto 0);
      awlen : in std_logic_vector(7 downto 0) := (others => '0');
      awsize : in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      awburst : in std_logic_vector(1 downto 0) := "01";
      awlock : in std_logic := '0';
      awcache : in std_logic_vector(3 downto 0) := (others => '0');
      awprot : in std_logic_vector(2 downto 0) := (others => '0');
      awvalid : in std_logic;
      awready : out std_logic;

      wdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : in std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0) := (others => '1');
      wlast : in std_logic := '1';
      wvalid : in std_logic;
      wready : out std_logic;

      bid : out std_logic_vector(config_c.id_width-1 downto 0);
      bresp : out std_logic_vector(1 downto 0);
      bvalid : out std_logic;
      bready : in std_logic;

      arid : in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      araddr : in std_logic_vector(config_c.address_width-1 downto 0);
      arlen : in std_logic_vector(7 downto 0) := (others => '0');
      arsize : in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      arburst : in std_logic_vector(1 downto 0) := "01";
      arlock : in std_logic := '0';
      arcache : in std_logic_vector(3 downto 0) := (others => '0');
      arprot : in std_logic_vector(2 downto 0) := (others => '0');
      arvalid : in std_logic;
      arready : out std_logic;

      rid : out std_logic_vector(config_c.id_width-1 downto 0);
      rdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : out std_logic_vector(1 downto 0);
      rlast : out std_logic;
      rvalid : out std_logic;
      rready : in std_logic;

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t
      );
  end component;

  -- A bridge where the HPS is slave (f2h, f2sdram), as exported by the
  -- intel_agilex_5_soc Platform Designer component, driven from NSL
  -- records of configuration config_c.  Flat ports are named as the AXI
  -- signals of the exported interface, AxUSER is 8 bits wide.
  --
  -- reset_n_i is asynchronous, reset_n_o is it, released synchronously
  -- to clock_i, for the master logic.  While reset_n_o is asserted, no
  -- valid and no ready crosses the port, in either direction, whatever
  -- the master does.
  component hps_pd_slave_port is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      reset_n_o : out std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t;

      awid : out std_logic_vector(config_c.id_width-1 downto 0);
      awaddr : out std_logic_vector(config_c.address_width-1 downto 0);
      awlen : out std_logic_vector(7 downto 0);
      awsize : out std_logic_vector(2 downto 0);
      awburst : out std_logic_vector(1 downto 0);
      awlock : out std_logic;
      awcache : out std_logic_vector(3 downto 0);
      awprot : out std_logic_vector(2 downto 0);
      awuser : out std_logic_vector(7 downto 0);
      awvalid : out std_logic;
      awready : in std_logic;

      wdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : out std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wlast : out std_logic;
      wvalid : out std_logic;
      wready : in std_logic;

      bid : in std_logic_vector(config_c.id_width-1 downto 0);
      bresp : in std_logic_vector(1 downto 0);
      bvalid : in std_logic;
      bready : out std_logic;

      arid : out std_logic_vector(config_c.id_width-1 downto 0);
      araddr : out std_logic_vector(config_c.address_width-1 downto 0);
      arlen : out std_logic_vector(7 downto 0);
      arsize : out std_logic_vector(2 downto 0);
      arburst : out std_logic_vector(1 downto 0);
      arlock : out std_logic;
      arcache : out std_logic_vector(3 downto 0);
      arprot : out std_logic_vector(2 downto 0);
      aruser : out std_logic_vector(7 downto 0);
      arvalid : out std_logic;
      arready : in std_logic;

      rid : in std_logic_vector(config_c.id_width-1 downto 0);
      rdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : in std_logic_vector(1 downto 0);
      rlast : in std_logic;
      rvalid : in std_logic;
      rready : out std_logic
      );
  end component;

  -- HPS and MPFE atoms with the HPS IO buffers, atom side of the
  -- bridges.  Wrapper internals: its architecture is generated from the
  -- project HPS configuration file, which generics must agree with.
  component hps_atoms is
    generic(
      h2f_used_c : boolean;
      h2f_data_width_c : natural;
      lwh2f_used_c : boolean;
      lwh2f_data_width_c : natural;
      f2h_used_c : boolean;
      f2h_data_width_c : natural;
      f2h_ace_c : hps_f2h_ace_t;
      f2sdram_used_c : boolean;
      f2sdram_data_width_c : natural;
      emif_used_c : boolean
      );
    port(
      hps_io_i : in std_ulogic_vector(0 to 47);
      hps_io_o : out std_ulogic_vector(0 to 47);
      hps_io_io : inout std_logic_vector(0 to 47);

      h2f_reset_o : out std_ulogic;
      user_clock_o : out std_ulogic_vector(0 to 1);
      warm_reset_request_n_o : out std_ulogic;
      warm_reset_ack_n_i : in std_ulogic;
      irq_i : in std_ulogic_vector(63 downto 0);
      gp_i : in std_ulogic_vector(31 downto 0);
      gp_o : out std_ulogic_vector(31 downto 0);

      h2f_clock_i : in std_ulogic;
      h2f_o : out hps_master_fwd_t;
      h2f_i : in hps_master_bwd_t;
      lwh2f_clock_i : in std_ulogic;
      lwh2f_o : out hps_master_fwd_t;
      lwh2f_i : in hps_master_bwd_t;
      f2h_clock_i : in std_ulogic;
      f2h_i : in hps_slave_fwd_t;
      f2h_o : out hps_slave_bwd_t;
      f2sdram_clock_i : in std_ulogic;
      f2sdram_i : in hps_slave_fwd_t;
      f2sdram_o : out hps_slave_bwd_t;

      emif_o : out hps_emif_o_t;
      emif_i : in hps_emif_i_t
      );
  end component;

  -- One register stage of a path between the HPS and the fabric
  -- core, in a boundary hyper-register.  to_periphery_c tells the
  -- direction.  No reset.
  component hps_boundary_register is
    generic(
      width_c : positive;
      to_periphery_c : boolean
      );
    port(
      clock_i : in std_ulogic;
      data_i : in std_ulogic_vector(width_c-1 downto 0);
      data_o : out std_ulogic_vector(width_c-1 downto 0)
      );
  end component;

  -- One channel of a bridge between the HPS and the fabric, as the
  -- vendor ready latency adapters do it.  Valid and data go through a
  -- boundary register towards the receiver, ready through one towards
  -- the source.
  --
  -- With fifo_c, the receiving side has a skid buffer that takes the
  -- beats in flight: both ports follow the valid/ready handshake rules,
  -- the source sees a registered ready.  Without fifo_c, valid, data
  -- and ready are only delayed: the receiver must be built to accept
  -- beats sent while its ready was asserted two cycles before (HPS
  -- side of response channels).
  --
  -- to_periphery_c: whether valid and data go from the core to the
  -- HPS.  reset_n_i resets the skid buffer.
  component hps_bridge_channel is
    generic(
      width_c : positive;
      to_periphery_c : boolean;
      fifo_c : boolean
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_valid_i : in std_ulogic;
      in_data_i : in std_ulogic_vector(width_c-1 downto 0);
      in_ready_o : out std_ulogic;

      out_valid_o : out std_ulogic;
      out_data_o : out std_ulogic_vector(width_c-1 downto 0);
      out_ready_i : in std_ulogic
      );
  end component;

end package;
