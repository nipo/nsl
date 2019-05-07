
class AteBase:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def shift_bytes(self, opts, length, data):
        for off in range(0, length, 0x20):
            size = min(32, length - off)
            
            self.pipe.put([0x00 | opts | (size - 1)])
            if data:
                self.pipe.put(list(data[off:off+size]))

    def shift_bits(self, opts, length, data):
        self.pipe.put([0xe0 | opts | (length - 1)])
        if data is not None:
            self.pipe.put([data])

    def reset(self, cycles = 5):
        while cycles > 7:
            packs = min(cycles // 8, 16)
            self.pipe.put([0xb0 | (packs - 1)])
            cycles -= packs * 8
        if cycles:
            self.pipe.put([0x98 | (cycles - 1)])

    def rti(self, cycles = 5):
        while cycles > 7:
            packs = min(cycles // 8, 16)
            self.pipe.put([0xa0 | (packs - 1)])
            cycles -= packs * 8
        if cycles:
            self.pipe.put([0x90 | (cycles - 1)])

    def swd_to_jtag(self):
        self.reset(50)
        self.pipe.put([0x82])
        self.reset()

    def dr_capture(self):
        self.pipe.put([0x80])

    def ir_capture(self):
        self.pipe.put([0x81])

    def divisor(self, value):
        assert 1 <= value <= 0x20
        self.pipe.put([0xc0 | (value - 1)])

    def shift(self, tdi, tdo, length):
        bytelength = length // 8
        if bytelength:
            if tdi:
                tdi_bytes = (tdi & ((1 << (bytelength * 8)) - 1)).to_bytes(bytelength, "little")
            else:
                tdi_bytes = None
            if tdo:
                tdo_bytes = (tdo & ((1 << (bytelength * 8)) - 1)).to_bytes(bytelength, "little")
            else:
                tdo_bytes = None
            self.shift_bytes(tdi_bytes, tdo_bytes, bytelength)
        if length > bytelength * 8:
            if tdi:
                tdi_bits = tdi >> (bytelength * 8)
            else:
                tdi_bits = None
            if tdo:
                tdo_bits = tdo >> (bytelength * 8)
            else:
                tdo_bits = None
            self.shift_bits(tdi_bits, tdo_bits, length - bytelength * 8)
            
            
class AteCmd(AteBase):
    def shift_bytes(self, tdi, tdo, length):
        opts = 0
        if tdi:
            opts |= 0x40
        if tdo:
            opts |= 0x20
        assert 1 <= length <= 0x20

        AteBase.shift_bytes(self, opts, length, tdi)

    def shift_bits(self, tdi, tdo, length):
        assert 1 <= length <= 8
        opts = 0
        if tdi is not None:
            opts |= 0x10
        if tdo is not None:
            opts |= 0x08
        AteBase.shift_bits(self, opts, length, tdi)

class AteRsp(AteBase):
    def shift_bytes(self, tdi, tdo, length):
        opts = 0
        if tdi:
            opts |= 0x40
        if tdo:
            opts |= 0x20
        assert 1 <= length <= 0x20

        AteBase.shift_bytes(self, opts, length, tdo)

    def shift_bits(self, tdi, tdo, length):
        assert 1 <= length <= 8
        opts = 0
        if tdi is not None:
            opts |= 0x10
        if tdo is not None:
            opts |= 0x08
        AteBase.shift_bits(self, opts, length, tdo)

class Tap:
    def __init__(self, master, ir_len, ir_pre = 0, ir_post = 0, dr_pre = 0, dr_post = 0):
        self.master = master
        self.ir_len = ir_len
        self.ir_pre = ir_pre
        self.ir_post = ir_post
        self.dr_pre = dr_pre
        self.dr_post = dr_post

    def divisor(self, value = 16):
        self.master.divisor(16)

    def ir_io(self, tdi = -1, tdo = None):
        self.master.ir_capture()
        self.master.shift(-1, None, self.ir_pre)
        self.master.shift(tdi, tdo, self.ir_len)
        self.master.shift(-1, None, self.ir_post)

    def dr_io(self, length, tdi = 0, tdo = None):
        self.master.dr_capture()
        self.master.shift(-1, None, self.ir_pre)
        self.master.shift(tdi, tdo, length)
        self.master.shift(-1, None, self.ir_post)

    def run(self, cycles = 1):
        self.master.rti(cycles)
