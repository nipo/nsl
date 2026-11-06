"""Agilex 5 HPS configuration to HDL conversion.

A pass turns an nsl-agilex5-hps configuration file into the HPS atom
layer of nsl_altera (VHDL) and the HPS boot configuration assignment of
the Quartus project.
"""

from __future__ import annotations

from gbs.base import BaseBackend, BaseDispatcher, BasePass
from gbs.build.task import BuildError, ResourceTypology, Task

from .config import HpsConfig, HpsConfigError
from .handoff import Handoff
from .vhdl import AtomLayer

FILE_TYPE = "nsl-agilex5-hps"
LIBRARY = "nsl_altera"


class HpsGenerateTask(Task):
    """Write the atom layer and the boot configuration of a configuration"""

    def __init__(self, dispatcher, inputs, outputs):
        super().__init__(
            dispatcher,
            "nsl_agilex5_hps_generate",
            inputs=inputs,
            outputs=outputs,
            description="Generate Agilex 5 HPS atom layer",
        )

    async def work(self) -> None:
        source, = self.inputs_of_type(FILE_TYPE)
        vhdl, = self.outputs_of_type("vhdl")
        tcl, = self.outputs_of_type("quartus-pin-assignment")
        try:
            config = HpsConfig.load(source.path)
        except HpsConfigError as e:
            raise BuildError(str(e))
        vhdl.path.parent.mkdir(parents=True, exist_ok=True)
        vhdl.path.write_text(AtomLayer(config).render())
        tcl.path.write_text(Handoff(config).tcl())


class HpsGenerateDispatcher(BaseDispatcher):
    def __init__(self, context):
        super().__init__(context, "nsl-agilex5-hps", tool_name="nsl-agilex5-hps")
        self.task = None

    async def process(self) -> None:
        if self.task is not None:
            return
        sources = list(self.context.filter_pending(file_type=FILE_TYPE))
        if not sources:
            return
        if len(sources) > 1:
            raise BuildError("More than one Agilex 5 HPS configuration: "
                             + ", ".join(str(s.path) for s in sources))
        source, = sources
        out = self.context.output_path / "nsl_agilex5_hps"
        vhdl = self.context.get_resource(
            out / "hps_atoms.vhd",
            file_type="vhdl",
            library=LIBRARY,
            typology=ResourceTypology.INTERMEDIATE,
            generated_by=self.name,
        )
        tcl = self.context.get_resource(
            out / "hps_handoff.tcl",
            file_type="quartus-pin-assignment",
            typology=ResourceTypology.INTERMEDIATE,
            generated_by=self.name,
        )
        self.task = HpsGenerateTask(self, inputs=[source], outputs=[vhdl, tcl])
        self.attach_definition_dependencies(self.task)


class HpsGeneratePass(BasePass):
    name = "nsl-agilex5-hps"
    input_types = {FILE_TYPE}
    output_types = {"vhdl", "quartus-pin-assignment"}
    types_with_library = set()

    def probe(self) -> str | None:
        part = ((self.config.get("target") or {}).get("part") or "").upper()
        if part and not part.startswith("A5E"):
            return f"target part {part!r} is not an Agilex 5"
        return None

    def dispatchers(self, context):
        return [HpsGenerateDispatcher(context)]


class HpsGenerateBackend(BaseBackend):
    def __init__(self):
        super().__init__("gbs.plugin.nsl.agilex5_hps")

    def contribute_passes(self, config, output_types, project_config=None, gbs_config=None):
        if not (output_types & HpsGeneratePass.output_types):
            return []
        return [HpsGeneratePass(config, project_config, gbs_config)]
