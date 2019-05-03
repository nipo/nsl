
class MasterCmd:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def divisor(self, value):
        self.pipe.put([value])

    def start(self):
        self.pipe.put([0x20])

    def stop(self):
        self.pipe.put([0x21])

    def read(self, data, ack):
        self.pipe.put([0x80 | (int(bool(ack)) << 6) | (len(data) - 1)])

    def write(self, data, ack = True):
        self.pipe.put([0x40 | (len(data) - 1)])
        self.pipe.put(list(data))

class MasterRsp:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def divisor(self, value):
        self.pipe.put([0])

    def start(self):
        self.pipe.put([0x00])

    def stop(self):
        self.pipe.put([0x00])

    def read(self, data, ack):
        self.pipe.put(list(data))

    def write(self, data, ack = True):
        self.pipe.put([1] * (len(data) - 1))
        self.pipe.put([int(ack)])

class Memory:
    def __init__(self, bus, addr):
        self.bus = bus
        self.addr = addr

    def write(self, tag, addr, data):
        self.bus.start()
        self.bus.write([self.addr << 1, addr >> 8, addr & 0xff] + data)
        self.bus.stop()
        self.bus.flush(tag = tag)

    def read(self, tag, addr, data):
        self.bus.start()
        self.bus.write([self.addr << 1, addr >> 8, addr & 0xff])
        self.bus.start()
        self.bus.write([(self.addr << 1) | 1])
        self.bus.read(data, False)
        self.bus.stop()
        self.bus.flush(tag = tag)
