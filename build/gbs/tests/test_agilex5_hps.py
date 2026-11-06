from pathlib import Path

import pytest
import yaml

from gbs.plugin.nsl.agilex5_hps.config import HpsConfig, HpsConfigError
from gbs.plugin.nsl.agilex5_hps.handoff import Handoff
from gbs.plugin.nsl.agilex5_hps.vhdl import AtomLayer

DATA = Path(__file__).parent / "data"


def ghrd():
    return yaml.safe_load((DATA / "de25_nano_ghrd.yaml").read_text())


class TestHandoff:
    def test_matches_vendor_ip(self):
        """The DE25-Nano reference design settings give the HPS_ISW_DATA
        string the vendor IP generates for them"""
        config = HpsConfig.load(DATA / "de25_nano_ghrd.yaml")
        expected = (DATA / "de25_nano_ghrd.isw").read_text().rstrip("\n")
        assert Handoff(config).isw_data() == expected

    def test_bridges_and_memory_flags(self):
        data = ghrd()
        del data["emif"]
        data["bridges"] = {"lwh2f": {"data_width": 32, "address_width": 29}}
        isw = Handoff(HpsConfig(data)).isw_data()
        assert " SDM DDR 0 " in isw
        assert " intfcsel f2soc 0 intfcsel f2sdram 0 " in isw


class TestConfig:
    def error(self, data):
        with pytest.raises(HpsConfigError) as e:
            HpsConfig(data)
        return str(e.value)

    def test_unknown_key(self):
        data = ghrd()
        data["cpu"]["a78"] = True
        assert "unknown a78" in self.error(data)

    def test_missing_pin(self):
        data = ghrd()
        del data["pins"][47]
        assert "missing [47]" in self.error(data)

    def test_missing_clock(self):
        data = ghrd()
        del data["clock_manager"]["mainpllgrp.pllm.mdiv"]
        assert "missing mainpllgrp.pllm.mdiv" in self.error(data)

    def test_f2sdram_needs_emif(self):
        data = ghrd()
        del data["emif"]
        assert "needs the HPS EMIF" in self.error(data)

    def test_bridge_width(self):
        data = ghrd()
        data["bridges"]["h2f"]["data_width"] = 256
        assert "h2f.data_width" in self.error(data)


class TestAtomLayer:
    def render(self, data):
        return AtomLayer(HpsConfig(data)).render()

    def test_io_ports_follow_pin_modes(self):
        text = self.render(ghrd())
        # USB0 STP, output only
        assert "hps_ioa_2_bidir_out : out std_ulogic" in text
        assert "hps_ioa_2_bidir_in" not in text
        # HPS_OSC_CLK, input only
        assert "hps_iob_4_bidir_in : in std_ulogic" in text
        assert "hps_iob_4_bidir_out" not in text
        # Unused pin
        assert "hps_iob_9_bidir" not in text

    def test_mpfe_link_only_with_mpfe(self):
        data = ghrd()
        assert "ccu_dmi0_awready" in self.render(data)
        del data["emif"]
        data["bridges"] = {"lwh2f": {"data_width": 32, "address_width": 29}}
        text = self.render(data)
        assert "ccu_dmi0_awready" not in text
        assert "tennm_sm_soc_mpfe" not in text
        assert "      soc2fpga_aw_addr" not in text
        assert "lwsoc2fpga_aw_addr" in text
