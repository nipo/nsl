from . import framed

class Committed(framed.Framed):
    def __init__(self, filename):
        framed.Framed.__init__(self, filename)

    def put(self, frame, commit = True, **kwargs):
        frame = list(frame)
        frame.append(1 if commit else 0)
        framed.Framed.put(self, frame, **kwargs)
