import click
from crobe.cli import base

def t(root, base, c):
    c = [
        root.cmd_dr_shift(root.IR_USER1, base, 32),
        root.cmd_run(c),
        root.cmd_dr_shift(root.IR_USER1, 0x80, 32, read_tdo = True),
        root.cmd_dr_shift(-1, None),
        root.cmd_run(1),
    ]
    root.execute(c)
    return int(c[2].tdo) - base

@click.command(help = "Check TAP")
@click.option('-r', '--root', type = base.ROOT)
def check(root):
    root.port.port.tap_reset(5)
    root.port.port.run(1)

    start = 0x100
    for i in range(1, 129):
        res = t(root, start, i)
        print(f"Test run from {start:#x} during {i:#x}: {res:#x}")
        assert i - 4 <= res <= i+4

if __name__ == "__main__":
    check()
    


