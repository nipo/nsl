from crobe.component.riscv import jtag_dtm
from crobe.protocol import jtag
from crobe.part_id import PartId

@jtag.Chain.db.register(PartId(0,0,0))
class NeoRV32Tap(jtag_dtm.RvTap):
    pass

