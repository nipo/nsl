#!/usr/bin/env python2

from nsl.sized import Sized
from nsl.framed import Framed
import sys
import random

framed = Framed(sys.argv[1])
sized = Sized(sys.argv[2])

for txn in range(40):
    size = random.randint(1, 1500)

    frame = []
    for i in range(size - 1):
        d = random.randint(0, 255)
        frame.append(d)
    framed.put(frame, end_delay = random.randint(0, 512))
    sized.put(frame, end_delay = random.randint(0, 512))
