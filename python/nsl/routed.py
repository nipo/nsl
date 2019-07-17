
from . import framed

class Routed(framed.Framed):
    def __init__(self, filename):
        framed.Framed.__init__(self, filename)
        self.last_tag = 0

    def put(self, dst, src, frame, tag = None, **kwargs):
        if tag is None:
            tag = (self.last_tag + 1) & 0xff

        header = [(src<<4) | dst, tag]

        self.last_tag = tag

        framed.Framed.put(self, header + frame, **kwargs)

class RoutedTarget:
    def __init__(self, routed, dst, src):
        self.routed = routed
        self.dst = dst
        self.src = src

    def put(self, frame, **kwargs):
        self.routed.put(self.dst, self.src, frame, **kwargs)

class SplitRouted(RoutedTarget):
    def __init__(self, routed, dst, src):
        RoutedTarget.__init__(self, routed, dst, src)
        self.pending = []

    def put(self, cmds):
        self.pending += cmds

    def flush(self, **kwargs):
        RoutedTarget.put(self, self.pending, **kwargs)
        self.pending = []

