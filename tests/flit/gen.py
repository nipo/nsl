#!/usr/bin/env python2

import sys
import random

framed = open(sys.argv[1], "w")
flit = open(sys.argv[2], "w")

def B(v, w):
    return bin(v)[2:].rjust(w, '0')

for txn in range(20):
    size = random.randint(1, 255)
    
    flit.write("%s %d\n" % (B(size), 0))

    for i in range(size - 1):
        d = random.randint(0, 255)
        framed.write("%s %d\n" % (B(d + (256 if i < size - 1 else 0)), random.randint(0, 4)))
        flit.write("%s %d\n" % (B(d), random.randint(0, 4)))

    d = random.randint(0, 255)
    framed.write("%s %d\n" % (B(d), random.randint(0, 4)))
    flit.write("%s %d\n" % (B(d), random.randint(0, 4)))
