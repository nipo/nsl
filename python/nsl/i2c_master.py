
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
    def __init__(self, bus, addr, addr_bytes = 2):
        self.bus = bus
        self.addr = addr
        self.addr_bytes = addr_bytes

    def write(self, addr, data, **kwargs):
        self.bus.start()
        mem_addr = list(addr.to_bytes(self.addr_bytes, "big"))
        self.bus.write([self.addr << 1]  + mem_addr + data)
        self.bus.stop()
        self.bus.flush(**kwargs)

    def read(self, addr, data, **kwargs):
        self.bus.start()
        mem_addr = list(addr.to_bytes(self.addr_bytes, "big"))
        self.bus.write([self.addr << 1] + mem_addr)
        self.bus.start()
        self.bus.write([(self.addr << 1) | 1])
        self.bus.read(data, False)
        self.bus.stop()
        self.bus.flush(**kwargs)
