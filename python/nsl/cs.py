
__all__ = ["MasterCmd", "MasterRsp"]

class Base:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)

class MasterCmd(Base):
    def write(self, reg, val):
        self.pipe.put([reg])
        for i in range(4):
            self.pipe.put([(val >> (8 * i)) & 0xff])

    def read(self, reg, val):
        self.pipe.put([0x80 | reg])

class MasterRsp(Base):
    def write(self, reg, val):
        self.pipe.put([reg])

    def read(self, reg, val):
        self.pipe.put([0x80 | reg])
        for i in range(4):
            self.pipe.put([(val >> (8 * i)) & 0xff])
