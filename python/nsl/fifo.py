
class FifoFile:
    def __init__(self, filename, width):
        self.output = open(filename, "w")
        self.width = width

    def put(self, data, mask = -1, delay = 0):
        for i in range(self.width - 1, -1, -1):
            v = (data >> i) & 1
            m = (mask >> i) & 1
            if m:
                self.output.write("%d" % v)
            else:
                self.output.write("-")
        self.output.write(" %d\n" % delay)
