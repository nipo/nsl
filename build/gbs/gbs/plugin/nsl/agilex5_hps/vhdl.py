"""Generation of the HPS atom layer (nsl_altera hps_atoms entity).

The HPS atom only takes an unconnected input where it has no hard route
to it (the MPFE link without MPFE, the input of an HPS IO pin without
input buffer), and Quartus only leaves a port unconnected when the
component does not declare it: a declared port left open gets tied to
its default, and the Fitter finds no route for the constant.  Which ports
exist hence depends on the configuration, the layer is generated from it.

The entity interface is fixed, it is the hps_atoms component of the
nsl_altera.hps package.  Bridges the configuration does not use have
their atom ports undeclared and their entity outputs idle.
"""

from __future__ import annotations

from pathlib import Path

from .config import HpsConfig
from . import tables


class AtomLayer:
    """VHDL text of the atom layer of a configuration"""

    ENTITY = """entity hps_atoms is
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
end entity;
"""

    IBUF = """  component tennm_ph2_io_ibuf is
    generic(
      buffer_usage : string := "REGULAR";
      bus_hold : string := "BUS_HOLD_OFF";
      equalization : string := "EQUALIZATION_OFF";
      io_standard : string := "IO_STANDARD_IOSTD_OFF";
      rzq_id : string := "RZQ_ID_RZQ0";
      schmitt_trigger : string := "SCHMITT_TRIGGER_OFF";
      termination : string := "TERMINATION_RT_OFF";
      toggle_speed : string := "TOGGLE_SPEED_SLOW";
      usage_mode : string := "USAGE_MODE_GPIO";
      vref : string := "VREF_OFF";
      weak_pull_down : string := "WEAK_PULL_DOWN_OFF";
      weak_pull_up : string := "WEAK_PULL_UP_OFF"
      );
    port(
      i : in std_logic;
      o : out std_logic
      );
  end component;
"""

    OBUF = """  component tennm_ph2_io_obuf is
    generic(
      buffer_usage : string := "REGULAR";
      dynamic_pull_up_enabled : string := "false";
      equalization : string := "EQUALIZATION_OFF";
      io_standard : string := "IO_STANDARD_IOSTD_OFF";
      open_drain : string := "OPEN_DRAIN_OFF";
      rzq_id : string := "RZQ_ID_RZQ0";
      slew_rate : string := "SLEW_RATE_SLOW";
      termination : string := "TERMINATION_SERIES_OFF";
      toggle_speed : string := "TOGGLE_SPEED_SLOW";
      usage_mode : string := "USAGE_MODE_GPIO"
      );
    port(
      i : in std_logic;
      oe : in std_logic;
      o : out std_logic
      );
  end component;
"""

    # Bridge -> (atom port prefix of the HPS, ports kept when unused)
    HPS_BRIDGE_PORTS = {
        "h2f": ("soc2fpga_", ("soc2fpga_port_size_config_0", "soc2fpga_port_size_config_1")),
        "lwh2f": ("lwsoc2fpga_", ("lwsoc2fpga_port_size_config_0",)),
    }

    # MPFE ports of the HPS link, connected whenever the MPFE is
    MPFE_LINK_PORTS = ("f2soc_clk_fdo_aps", "f2sdram_flush_req", "f2sdram_flush_ack",
                       "f2sdram_tbu_pmu_irpt", "f2sdram_tbu_ras_irpt",
                       "f2sdram_bridge_rst_n", "f2sdram_port_size_config",
                       "mpu_ccu_clk")

    def __init__(self, config: HpsConfig):
        self.config = config

    # -- helpers

    @staticmethod
    def vtype(width: int) -> str:
        if width == 1:
            return "std_ulogic"
        return f"std_ulogic_vector({width - 1} downto 0)"

    @staticmethod
    def slv32(value: int) -> str:
        return f'x"{value:08x}"'

    @staticmethod
    def zero(width: int) -> str:
        return "'0'" if width == 0 else "(others => '0')"

    @staticmethod
    def component(name: str, generics: list[str], ports: list[tuple[str, str, int]]) -> str:
        lines = [f"  component {name} is", "    generic("]
        lines.append(";\n".join(f"      {g}" for g in generics))
        lines += ["      );", "    port("]
        lines.append(";\n".join(f"      {n} : {d} {AtomLayer.vtype(w)}" for n, d, w in ports))
        lines += ["      );", "  end component;", ""]
        return "\n".join(lines)

    @staticmethod
    def instance(label: str, name: str, generics: list[tuple[str, str]],
                 ports: list[tuple[str, str]]) -> str:
        lines = [f"  {label}: {name}", "    generic map("]
        lines.append(",\n".join(f"      {k} => {v}" for k, v in generics))
        lines += ["      )", "    port map("]
        lines.append(",\n".join(f"      {k} => {v}" for k, v in ports))
        lines += ["      );", ""]
        return "\n".join(lines)

    def bridge(self, name: str):
        return self.config.bridges.get(name)

    # -- atom generics

    def hps_generics(self) -> list[tuple[str, str]]:
        c = self.config
        cpu = c.cpu
        if cpu.a76_core2 and cpu.a76_core3:
            a76 = "DUAL"
        elif cpu.a76_core2 or cpu.a76_core3:
            a76 = "SINGLE"
        else:
            a76 = "OFF"
        h2f = self.bridge("h2f")
        lwh2f = self.bridge("lwh2f")
        return [
            ("soc_hps_wrapper_h2f_addr_width", self.slv32(h2f.address_width if h2f else 38)),
            ("soc_hps_wrapper_h2f_data_width", self.slv32(h2f.data_width if h2f else 0)),
            ("soc_hps_wrapper_hps_a55_core_state",
             '"HPS_A55_CORE_STATE_BOTH_ON"' if cpu.a55 else '"HPS_A55_CORE_STATE_BOTH_OFF"'),
            ("soc_hps_wrapper_hps_a76_core_selection", f'"HPS_A76_CORE_SELECTION_{a76}"'),
            ("soc_hps_wrapper_hps_l3_memory_size", f'"HPS_L3_MEMORY_SIZE_{cpu.l3_cache_mb}_MB"'),
            ("soc_hps_wrapper_lwh2f_addr_width", self.slv32(lwh2f.address_width if lwh2f else 29)),
            ("soc_hps_wrapper_lwh2f_data_width", self.slv32(lwh2f.data_width if lwh2f else 0)),
            ("soc_hps_wrapper_powerdown_mode", '"FALSE"'),
            ("soc_hps_wrapper_powermode_freq_hz", self.slv32(cpu.mpu_frequency_hz)),
        ]

    def mpfe_generics(self) -> list[tuple[str, str]]:
        f2h = self.bridge("f2h")
        f2sdram = self.bridge("f2sdram")
        width = f2sdram.data_width if f2sdram else 256
        topology = {"1x16": "SINGLE_16_BIT", "1x32": "SINGLE_32_BIT"}[
            self.config.emif_topology or "1x16"]
        return [
            ("mpfe_enable", '"MPFE_ENABLE_ENABLE"'),
            ("mpfe_f2sdram_port_width", f'"MPFE_F2SDRAM_PORT_WIDTH_DATA_WIDTH_{width}"'),
            ("topology", f'"TOPOLOGY_{topology}"'),
            ("f2h_addr_width", self.slv32(f2h.address_width if f2h else 40)),
            ("f2h_data_width", self.slv32(f2h.data_width if f2h else 0)),
            ("f2sdram_addr_width", self.slv32(f2sdram.address_width if f2sdram else 40)),
            ("f2sdram_data_width", self.slv32(f2sdram.data_width if f2sdram else 0)),
        ]

    HPS_GENERIC_DECLS = [
        "soc_hps_wrapper_h2f_addr_width : std_logic_vector(31 downto 0)",
        "soc_hps_wrapper_h2f_data_width : std_logic_vector(31 downto 0)",
        "soc_hps_wrapper_hps_a55_core_state : string",
        "soc_hps_wrapper_hps_a76_core_selection : string",
        "soc_hps_wrapper_hps_l3_memory_size : string",
        "soc_hps_wrapper_lwh2f_addr_width : std_logic_vector(31 downto 0)",
        "soc_hps_wrapper_lwh2f_data_width : std_logic_vector(31 downto 0)",
        "soc_hps_wrapper_powerdown_mode : string",
        "soc_hps_wrapper_powermode_freq_hz : std_logic_vector(31 downto 0)",
    ]

    MPFE_GENERIC_DECLS = [
        "mpfe_enable : string",
        "mpfe_f2sdram_port_width : string",
        "topology : string",
        "f2h_addr_width : std_logic_vector(31 downto 0)",
        "f2h_data_width : std_logic_vector(31 downto 0)",
        "f2sdram_addr_width : std_logic_vector(31 downto 0)",
        "f2sdram_data_width : std_logic_vector(31 downto 0)",
    ]

    # -- port selection

    def hps_ports(self) -> list[tuple[str, str, int, str]]:
        """HPS atom ports to declare, with their actual"""
        c = self.config
        ports = []
        for name, direction, width, actual, group in tables.HPS_PORTS:
            if group == "link" and not c.mpfe_used:
                continue
            skipped = False
            for bridge, (prefix, kept) in self.HPS_BRIDGE_PORTS.items():
                if name.startswith(prefix) and name not in kept and bridge not in c.bridges:
                    skipped = True
            if skipped:
                continue
            ports.append((name, direction, width, actual))
        for index, pin in enumerate(c.pins):
            bank, number = ("a", index + 1) if index < 24 else ("b", index - 23)
            if pin.has_input():
                ports.append((f"hps_io{bank}_{number}_bidir_in", "in", 1, f"io_in_s({index})"))
            if pin.has_output():
                ports.append((f"hps_io{bank}_{number}_bidir_out", "out", 1, f"io_out_s({index})"))
        return sorted(ports)

    def mpfe_ports(self) -> list[tuple[str, str, int, str]]:
        """MPFE atom ports to declare, with their actual"""
        c = self.config
        ports = []
        for name, direction, width, actual in tables.MPFE_PORTS:
            link = (actual.startswith("mpfe_") or name in self.MPFE_LINK_PORTS)
            if not link:
                if name.startswith("f2soc_") and "f2h" not in c.bridges:
                    continue
                if name.startswith("f2sdram_") and "f2sdram" not in c.bridges:
                    continue
                if name.startswith("io96b0_") and c.emif_topology is None:
                    continue
            ports.append((name, direction, width, actual))
        return ports

    # -- text

    def checks(self) -> str:
        c = self.config
        lines = []
        for name in ("h2f", "lwh2f", "f2h", "f2sdram"):
            b = self.bridge(name)
            used = "true" if b else "false"
            lines += [
                f"  assert {name}_used_c = {used}",
                f'    report "nsl_altera.hps: {name} is {"" if b else "not "}in use in '
                f'{self.origin_name()}"',
                "    severity failure;",
            ]
            if b:
                lines += [
                    f"  assert {name}_data_width_c = {b.data_width}",
                    f'    report "nsl_altera.hps: {name} is {b.data_width}-bit wide in '
                    f'{self.origin_name()}"',
                    "    severity failure;",
                ]
        emif = "true" if c.emif_topology else "false"
        lines += [
            f"  assert emif_used_c = {emif}",
            f'    report "nsl_altera.hps: HPS EMIF is {"" if c.emif_topology else "not "}in use in '
            f'{self.origin_name()}"',
            "    severity failure;",
        ]
        return "\n".join(lines) + "\n"

    def origin_name(self) -> str:
        return Path(self.config.origin).name

    def constants(self) -> str:
        c = self.config
        h2f = self.bridge("h2f")
        f2sdram = self.bridge("f2sdram")
        # Tie-offs of the vendor IP (hps_tieoffs.csv, mpfe_tieoffs.csv)
        if h2f is None:
            h2f_size = "11"
        else:
            h2f_size = {32: "00", 64: "01", 128: "10"}[h2f.data_width]
        f2sdram_size = {64: "00", 128: "01", 256: "10"}[f2sdram.data_width if f2sdram else 256]
        lwh2f_size = "1" if "lwh2f" in c.bridges else "0"
        return (f'  constant h2f_size_c : std_ulogic_vector(1 downto 0) := "{h2f_size}";\n'
                f"  constant lwh2f_size_c : std_ulogic := '{lwh2f_size}';\n"
                f'  constant f2sdram_size_c : std_ulogic_vector(1 downto 0) := "{f2sdram_size}";\n')

    def idle(self, target: str, fields) -> list[str]:
        return [f"  {target}.{n} <= {self.zero(w)};" for n, w in fields]

    def io_buffers(self) -> list[str]:
        lines = []
        for index, pin in enumerate(self.config.pins):
            if pin.mode == "input":
                lines += [f"  io{index}_in: tennm_ph2_io_ibuf",
                          f"    port map(i => hps_io_i({index}), o => io_in_s({index}));"]
            elif pin.mode in ("bidir", "bidir_open_drain", "i2c"):
                lines += [f"  io{index}_in: tennm_ph2_io_ibuf",
                          f"    port map(i => hps_io_io({index}), o => io_in_s({index}));"]
            if pin.mode == "output":
                lines += [f"  io{index}_out: tennm_ph2_io_obuf",
                          f"    port map(i => io_out_s({index}), oe => '1', o => hps_io_o({index}));"]
            elif pin.mode == "bidir":
                lines += [f"  io{index}_out: tennm_ph2_io_obuf",
                          f"    port map(i => io_out_s({index}), oe => '1', o => hps_io_io({index}));"]
            elif pin.mode == "bidir_open_drain":
                lines += [f"  io{index}_out: tennm_ph2_io_obuf",
                          '    generic map(open_drain => "OPEN_DRAIN_ON")',
                          f"    port map(i => io_out_s({index}), oe => '1', o => hps_io_io({index}));"]
            elif pin.mode == "i2c":
                # The HPS output drives the line low when set, as the
                # vendor IP connects it.
                lines += [f"  io{index}_out: tennm_ph2_io_obuf",
                          f"    port map(i => '0', oe => io_out_s({index}), o => hps_io_io({index}));"]
            if pin.mode != "output":
                lines.append(f"  hps_io_o({index}) <= '0';")
        return lines

    def render(self) -> str:
        c = self.config
        hps_ports = self.hps_ports()
        decl = [self.component("tennm_soc_hps", self.HPS_GENERIC_DECLS,
                               [(n, d, w) for n, d, w, _ in hps_ports])]
        if c.mpfe_used:
            mpfe_ports = self.mpfe_ports()
            decl.append(self.component("tennm_sm_soc_mpfe", self.MPFE_GENERIC_DECLS,
                                       [(n, d, w) for n, d, w, _ in mpfe_ports]))
        if any(p.has_input() for p in c.pins):
            decl.append(self.IBUF)
        if any(p.has_output() for p in c.pins):
            decl.append(self.OBUF)
        decl.append(self.constants())
        decl.append("  signal io_in_s, io_out_s : std_ulogic_vector(0 to 47);")
        if c.mpfe_used:
            decl += [f"  signal {s} : {self.vtype(w)};" for s, w in tables.LINK_SIGNALS]
        if "f2sdram" in c.bridges:
            decl += ["  signal f2sdram_awaddr_s, f2sdram_araddr_s : std_ulogic_vector(43 downto 0);",
                     "  signal f2sdram_awuser_s, f2sdram_aruser_s : std_ulogic_vector(24 downto 0);"]

        body = [self.checks()]
        body.append(self.instance("hps", "tennm_soc_hps", self.hps_generics(),
                                  [(n, a) for n, _, _, a in hps_ports]))
        if c.mpfe_used:
            body.append(self.instance("mpfe", "tennm_sm_soc_mpfe", self.mpfe_generics(),
                                      [(n, a) for n, _, _, a in mpfe_ports]))
        body += self.io_buffers()
        body.append("")

        if "h2f" not in c.bridges:
            body += self.idle("h2f_o", tables.HPS_MASTER_FWD_FIELDS)
        if "lwh2f" in c.bridges:
            body += ["  -- lwsoc2fpga ports are narrower than the shared record",
                     "  lwh2f_o.awaddr(39 downto 32) <= (others => '0');",
                     "  lwh2f_o.araddr(39 downto 32) <= (others => '0');",
                     "  lwh2f_o.wdata(127 downto 32) <= (others => '0');",
                     "  lwh2f_o.wstrb(15 downto 4) <= (others => '0');"]
        else:
            body += self.idle("lwh2f_o", tables.HPS_MASTER_FWD_FIELDS)
        if "f2h" not in c.bridges:
            body += self.idle("f2h_o", tables.HPS_SLAVE_BWD_FIELDS)
        if "f2sdram" in c.bridges:
            body += ['  f2sdram_awaddr_s <= "0000" & f2sdram_i.awaddr;',
                     '  f2sdram_araddr_s <= "0000" & f2sdram_i.araddr;',
                     "  -- SMMU stream ID part, tied as without SMMU",
                     '  f2sdram_awuser_s <= "00000000000000011" & f2sdram_i.awuser;',
                     '  f2sdram_aruser_s <= "00000000000000011" & f2sdram_i.aruser;']
        else:
            body += self.idle("f2sdram_o", tables.HPS_SLAVE_BWD_FIELDS)
        if c.emif_topology is None:
            body += self.idle("emif_o", tables.HPS_EMIF_O_FIELDS)

        return "\n".join([
            f"-- HPS atom layer, generated by gbs.plugin.nsl.agilex5_hps from",
            f"-- {self.origin_name()}.",
            "",
            "library ieee;",
            "use ieee.std_logic_1164.all;",
            "",
            "library nsl_altera;",
            "use nsl_altera.hps.all;",
            "",
            self.ENTITY,
            "architecture beh of hps_atoms is",
            "",
            "\n".join(decl),
            "",
            "begin",
            "",
            "\n".join(body),
            "",
            "end architecture;",
            "",
        ])
