
class MasterCmd:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def current_set(self, channel, value):
        channel = int(channel) & 7
        value = int(value) & 0xffff
        self.pipe.put([channel, value >> 8, value & 0xff])

    def target_set(self, target):
        target = int(target) & 0xffff
        self.pipe.put([0x08, target >> 8, target & 0xff])

    def increment_set(self, increment):
        increment = int(increment * 2 ** 16) & 0xffffffff
        self.pipe.put([0x09,
                       increment >> 24,
                       (increment >> 16) & 0xff,
                       (increment >> 8) & 0xff,
                       increment & 0xff,
        ])

class MasterRsp:
    def __init__(self, pipe):
        self.pipe = pipe

    def flush(self, **kwargs):
        self.pipe.flush(**kwargs)
        
    def current_set(self, channel, value):
        channel = int(channel) & 7
        self.pipe.put([channel])

    def target_set(self, target):
        self.pipe.put([0x08])

    def increment_set(self, increment):
        self.pipe.put([0x09])
