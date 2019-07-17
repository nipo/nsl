
from .fifo import FifoFile

class Framed(FifoFile):
    def __init__(self, filename):
        FifoFile.__init__(self, filename, 9)
        self.tlast = 1 << (self.width - 1)

    def put(self, frame, tag = None, delay = 0, end_delay = 0):
        dmask = self.tlast - 1
        for i, flit in enumerate(frame):
            is_last = i + 1 == len(frame)
            try:
                data, mask = flit
            except:
                data, mask = flit, (1 << (self.width - 1)) - 1

            FifoFile.put(self, (data & dmask) | (self.tlast if is_last else 0),
                         (mask & dmask) | self.tlast,
                         delay + (end_delay if is_last else 0))

class SplitFramed(Framed):
    def __init__(self, filename):
        Framed.__init__(self, filename)
        self.pending = []

    def put(self, parts):
        self.pending += parts

    def flush(self, **kwargs):
        Framed.put(self, self.pending, **kwargs)
        self.pending = []
