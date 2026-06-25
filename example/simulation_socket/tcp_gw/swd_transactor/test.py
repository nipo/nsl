from crobe.protocol import datagram, swd
from crobe.component.nsl.transactor.swd import SwdTransactor
from crobe.component.arm.sw_dp import SwDp
from crobe.component.arm.ap import Ap
from crobe.component.arm.mem_ap import MemAp
from crobe.part_id import PartId

@swd.Interface.db.register(PartId(14, 0x8, 0x4567, 0))
class MyDp(SwDp):
    max_freq = 4e6

    def debug_enable(self, enabled):
        self.ctrlstat = 0x50000020

@Ap.db.register(0x01234e11)
class MyAp(MemAp):
    pass

@datagram.Interface.db.register("swdtb")
class SwdTbIntf(swd.Interface):
    def __init__(self, port):
        self.transactor = SwdTransactor(port, 100e6)
        super().__init__(port)
        
    @property
    def turnaround_cycles(self):
        return self.transactor.turnaround_cycles

    @turnaround_cycles.setter
    def turnaround_cycles(self, cycles):
        self.transactor.turnaround_cycles = cycles

    def execute(self, op_list):
        self.transactor.execute(op_list)

    def freq_update(self, freq):
        return self.transactor.freq_update(freq)

if __name__ == '__main__':
    from crobe.cli.console import cli
    cli()
