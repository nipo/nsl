#!/usr/bin/env python2

import sys
import random

framed = open(sys.argv[1], "w")
flit = open(sys.argv[2], "w")

for txn in range(20):
    size = random.randint(1, 255)
    
    flit.write("%d %d\n" % (size, 0))

    for i in range(size - 1):
        d = random.randint(0, 255)
        framed.write("%d %d\n" % (d + (256 if i < size - 1 else 0), random.randint(0, 4)))
        flit.write("%d %d\n" % (d, random.randint(0, 4)))

    d = random.randint(0, 255)
    framed.write("%d %d\n" % (d, random.randint(0, 4)))
    flit.write("%d %d\n" % (d, random.randint(0, 4)))
