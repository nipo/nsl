
def read_write_test(bus, b = None):
    import secrets

    base = b or bus.base or 0

    for offset in range(32):
        for size in range(1, 65):
            print(f"Testing offset {offset:#4x}, size {size:#4x}")
            blob = secrets.token_bytes(size)
            bus.mem_write(base + offset, blob)
            readback = bus.mem_read(base + offset, size)
            if blob != readback:
                print(f"Failure!")
                print(f"expected: {blob.hex()}")
                print(f"actual  : {readback.hex()}")

if __name__ == "__main__":
    from crobe.root import root
    import sys

    from crobe.model import Bus32Component
    from crobe.component.model import Cpu
    r = root(sys.argv[1])

    bus = r.child_summon("0", "0")
    bus.start()
    base = None
    if len(sys.argv) > 2:
        base = int(sys.argv[2], 16)

    from crobe.target.model import Field
    field = Field()
    field.discover(r)
    for t in field.children:
        t.start()
        
    try:
        cpu = field.children_of_class(Cpu)[0]
    except:
        cpu = None
    if cpu:
        cpu.halt()
    read_write_test(bus, base)
