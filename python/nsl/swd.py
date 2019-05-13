
__all__ = ["MasterCmd", "MasterRsp", "Master"]

class Base:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)

    def turnaround(self, n):
        self.pipe.put([0xd0 | (n-1)])

    def reset(self, idcode):
        self.run(1, 50)
        self.bitbang(0xe79e, 16)
        self.run(1, 50)
        self.run(0, 10)
        self.read(0, 0, idcode)

class MasterCmd(Base):
    def read(self, ap, ad, val):
        if ap:
            self.pipe.put([0xb0 | (ad & 0x3)])
        else:
            self.pipe.put([0x90 | (ad & 0x3)])

    def write(self, ap, ad, val):
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

    def write(self, ap, ad, val):
        if ap:
            self.pipe.put([0xa1])
        else:
            self.pipe.put([0x81])
        
    def run(self, val, cycles):
        while cycles:
            c = min((cycles, 64))
            cycles -= c
            self.pipe.put([(int(bool(val)) << 6) | ((c - 1) & 0x3f)])

    def bitbang(self, value, length):
        self.pipe.put([0xe0 | ((length - 1) & 0x1f)])
