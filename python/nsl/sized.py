
from .fifo import FifoFile

class Sized(FifoFile):
    def __init__(self, filename):
        FifoFile.__init__(self, filename, 8)

    def put(self, frame, delay = 0, end_delay = 0):
        assert len(frame) <= 0xffff
        l = len(frame) - 1

        FifoFile.put(self, l >> 8, 0xff, 0)
        FifoFile.put(self, l & 0xff, 0xff, 0)

        for i, flit in enumerate(frame):
            is_last = i + 1 == len(frame)

            try:
                data, mask = flit
            except:
                data, mask = flit, (1 << self.width) - 1

            FifoFile.put(self, data, mask, delay + (end_delay if is_last else 0))
