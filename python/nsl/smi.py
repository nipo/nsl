
class MasterCmd:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def c22_read(self, phyad, addr, rdata, error):
        self.pipe.put([0x80 | phyad, addr])

    def c22_write(self, phyad, addr, data):
        self.pipe.put([0xa0 | phyad, addr, data >> 8, data & 0xff])

    def c45_addr(self, prtad, devad, addr):
        self.pipe.put([0x00 | prtad, devad, addr >> 8, addr & 0xff])

    def c45_write(self, prtad, devad, data):
        self.pipe.put([0x20 | prtad, devad, data >> 8, data & 0xff])

    def c45_read(self, prtad, devad, rdata, error):
        self.pipe.put([0x60 | prtad, devad])

    def c45_read_inc(self, prtad, devad, rdata, error):
        self.pipe.put([0x40 | prtad, devad])

class MasterRsp:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)

    def c22_read(self, phyad, addr, rdata, error):
        try:
            data, mask = rdata
        except:
            data = rdata
            mask = 0xff
        try:
            evalue, emask = error
        except:
            evalue = error
            emask = 0x1
        self.pipe.put([(data >> 8, mask >> 8), (data & 0xff, mask & 0xff), (evalue, emask)])

    def c22_write(self, phyad, addr, data):
        self.pipe.put([(0, 0)])

    c45_read_inc = c22_read
    c45_read = c22_read
    c45_addr = c22_write
    c45_write = c22_write
