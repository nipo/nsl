
__all__ = ["MasterCmd", "MasterRsp", "Master"]

class Base:
    def __init__(self, pipe):
        self.pipe = pipe
        self.select = 0

        
    SELECT = 2
    RDBUF = 3
    def ap_select(self, ap):
        if self.select >> 24 != ap:
            self.select = (self.select & ~0xff000000) | (ap << 24)
            self.write(False, self.SELECT, self.select)

    def reg_select(self, high):
        if 0xf & (self.select >> 4) != high:
            self.select = (self.select & ~0xf0) | (high << 4)
            self.write(False, self.SELECT, self.select)

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)

    def turnaround(self, n):
        self.pipe.put([0xd0 | (n-1)])

    def muxed_select(self, targetsel, idcode):
        self.run(1, 50)
        self.bitbang(0xe79e, 16)
        self.run(1, 50)
        self.run(0, 2)
        self.write(0, 3, targetsel, ack = None)
        self.run(0, 10)
        self.read(0, 0, idcode)

    def reset(self, idcode):
        self.run(1, 50)
        self.bitbang(0xe79e, 16)
        self.run(1, 50)
        self.run(0, 10)
        self.read(0, 0, idcode)

    def abort(self):
        self.pipe.put([0xc0])
        
class MasterCmd(Base):
    def divisor(self, value):
        self.pipe.put([0xc1])
        self.pipe.put(list(int(value-1).to_bytes(2, "little")))

    def read(self, ap, ad, val):
        if ap:
            self.pipe.put([0xb0 | (ad & 0x3)])
        else:
            self.pipe.put([0x90 | (ad & 0x3)])

    def write(self, ap, ad, val, ack = 1):
        if ap:
            self.pipe.put([0xa0 | (ad & 0x3)])
        else:
            self.pipe.put([0x80 | (ad & 0x3)])
        for i in range(4):
            self.pipe.put([(val >> (8 * i)) & 0xff])

    def run(self, val, cycles):
        while cycles:
            c = min((cycles, 64))
            cycles -= c
            self.pipe.put([(int(bool(val)) << 6) | ((c - 1) & 0x3f)])

    def bitbang(self, value, length):
        self.pipe.put([0xe0 | ((length - 1) & 0x1f)])
        for i in range(4):
            self.pipe.put([(value >> (8 * i)) & 0xff])

class MasterRsp(Base):
    def divisor(self, value):
        self.pipe.put([0xc1])

    def read(self, ap, ad, val):
        if ap:
            self.pipe.put([(0xb1, 0xf7 if val is None else 0xff)])
        else:
            self.pipe.put([(0x91, 0xf7 if val is None else 0xff)])
        if val is not None:
            for i in range(4):
                self.pipe.put([(val >> (8 * i)) & 0xff])
        else:
            for i in range(4):
                self.pipe.put([(0, 0)])

    def write(self, ap, ad, val, ack = 1):
        try:
            ack, mask = ack
        except:
            mask = 7
        if ack is None:
            ack, mask = 0, 0

        if ap:
            self.pipe.put([(0xa0 | ack, 0xf8 | mask)])
        else:
            self.pipe.put([(0x80 | ack, 0xf8 | mask)])
        
    def run(self, val, cycles):
        while cycles:
            c = min((cycles, 64))
            cycles -= c
            self.pipe.put([(int(bool(val)) << 6) | ((c - 1) & 0x3f)])

    def bitbang(self, value, length):
        self.pipe.put([0xe0 | ((length - 1) & 0x1f)])

class Ap:
    def __init__(self, dp, ap):
        self.dp = dp
        self.ap = ap
        self.sel = 0

    def rdbuf_get(self, value):
        self.dp.read(False, self.dp.RDBUF, value)

    def reg_write(self, reg, value):
        self.dp.ap_select(self.ap)
        self.dp.reg_select(reg >> 4)
        self.dp.write(True, (reg >> 2) & 0xf, value)

    def reg_read(self, reg, value):
        self.dp.ap_select(self.ap)
        self.dp.reg_select(reg >> 4)
        self.dp.read(True, (reg >> 2) & 0xf, value)

    def run(self, cycles = 10):
        self.dp.run(0, cycles)
        
class MemAp(Ap):
    CSW               = 0x00
    CSW_DBGSWEN       = (1 << 31)
    CSW_SPIDEN        = (1 << 23)
    CSW_DEVICEEN      = (1 << 6)
    TAR               = 0x04
    TAR_MSB           = 0x08
    DRW               = 0x0c
    BD0               = 0x10
    BD1               = 0x14
    BD2               = 0x18
    BD3               = 0x1c
    ACE_BARR          = 0x20
    BASE_MSB          = 0xf0
    CFG               = 0xf4
    CFG_BIG_ENDIAN    = 0x00000001
    CFG_LARGE_ADDRESS = 0x00000002
    CFG_LARGE_DATA    = 0x00000004
    BASE              = 0xf8
    
    def tar_set(self, addr):
        self.reg_write(self.TAR, addr)

    def csw_set(self, size_l2, inc):
        self.reg_write(self.CSW, size_l2 | (0x10 if inc else 0))

    def read32_multiple(self, addr, data_words):
        self.tar_set(addr)
        self.csw_set(2, True)
        self.reg_read(self.DRW, None)
        self.run()
        for d in data_words[:-1]:
            self.reg_read(self.DRW, d)
            self.run()
        self.rdbuf_get(data_words[-1])
        self.run()

    def write32_multiple(self, addr, data_words):
        self.tar_set(addr)
        self.csw_set(2, True)
        self.run()
        for d in data_words:
            self.reg_write(self.DRW, d)
            self.run()

    def read32(self, addr, data):
        self.tar_set(addr)
        self.csw_set(2, False)
        self.reg_read(self.DRW, None)
        self.run()
        self.rdbuf_get(data)
        self.run()

    def write32(self, addr, data):
        self.tar_set(addr)
        self.csw_set(2, False)
        self.reg_write(self.DRW, data)
        self.run()

