
class MasterCmd:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def div(self, div):
        self.pipe.put([0x20 | (div - 1)])

    def select(self, slave):
        self.pipe.put([slave])

    def unselect(self):
        self.pipe.put([0x1f])

    def shift_out(self, data):
        for offset in range(0, len(data), 0x40):
            chunk = data[offset : offset + 0x40]

            self.pipe.put([0x80 | (len(chunk) - 1)])
            self.pipe.put(chunk)

    def shift_in(self, data):
        for offset in range(0, len(data), 0x40):
            chunk = data[offset : offset + 0x40]

            self.pipe.put([0x40 | (len(chunk) - 1)])

    def shift_io(self, dout, din):
        assert len(dout) == len(din)

        for offset in range(0, len(data), 0x40):
            chunk = dout[offset : offset + 0x40]

            self.pipe.put([0xc0 | (len(chunk) - 1)])
            self.pipe.put(chunk)

class MasterRsp:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)

    def div(self, div):
        self.pipe.put([0x20 | (div - 1)])

    def select(self, slave):
        self.pipe.put([slave])

    def unselect(self):
        self.pipe.put([0x1f])

    def shift_out(self, data):
        for offset in range(0, len(data), 0x40):
            chunk = data[offset : offset + 0x40]

            self.pipe.put([0x80 | (len(chunk) - 1)])

    def shift_in(self, data):
        for offset in range(0, len(data), 0x40):
            chunk = data[offset : offset + 0x40]

            self.pipe.put([0x40 | (len(chunk) - 1)])
            self.pipe.put(chunk)

    def shift_io(self, dout, din):
        assert len(dout) == len(din)

        for offset in range(0, len(data), 0x40):
            chunk = din[offset : offset + 0x40]

            self.pipe.put([0xc0 | (len(chunk) - 1)])
            self.pipe.put(chunk)

class Master:
    def __init__(self, pipe):
        self.pipe = pipe
        self.div(32)

    def div(self, div):
        self.pipe.div(div)
        self.pipe.flush(end_delay = 50)

    def to_slave(self, data):
        l = len(data) - 1

        self.pipe.select(0)
        self.pipe.shift_out([0x80, l & 0xff, l >> 8])
        self.pipe.shift_out(data)
        self.pipe.unselect()
        self.pipe.flush()

    def from_slave(self, data):
        l = len(data) - 1

        self.pipe.select(0)
        self.pipe.shift_out([0xc0])
        self.pipe.shift_in([l & 0xff, l >> 8])
        self.pipe.shift_in(data)
        self.pipe.unselect()
        self.pipe.flush()
