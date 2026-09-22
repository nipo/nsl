"""A failing pass of the probe walker, as the DFI carried it.

Run with::

  acrobe run trace.py [resource-path] [passes=40] [size=0..5]
                      [pre=N] [offset=N] [tap=N]

An error count says a beat came back wrong and nothing about how: a
burst that came back one beat late, a burst that came back turned
round, and a burst that is the one the pass before wrote all read the
same through a count.

This runs one walker until a pass comes back with errors, with a
capture of the PHY's own side of the DFI armed over it.  It then
prints that pass and the last clean one the same way -- every command
that was not a deselect, every cycle a write burst went out on and
every cycle a read burst came back on, in time order -- and pairs each
read burst with the write to the same bank, row and column of the same
pass.  A pairing says which of the four a wrong burst is: the same
bytes, the same bytes moved along by so many beats, the bytes the
earlier pass wrote to that address, or none of those.

``size=`` picks the region, as in ``walk.py``.  The probe's whole pass
fits the window and is caught from the run; every larger region writes
itself out before it reads any of itself back, thousands of cycles
earlier than the window reaches, so those are caught on the walker's
own error line with the window standing before it.  A pairing is then
only to be had where a write of the same pass happens to fall inside
the window, and what the capture is read for is the command sequence
the bad beat arrived in.  ``pre=N`` overrides how much of the window
stands before the trigger.

The write path and the read path are left where the board record puts
them, so what a pass does here is what a walk does; ``offset`` and
``tap`` put them somewhere else, for a capture of a point the record
does not carry.
"""

import asyncio
import sys
import time

from acrobe_plugin.gatecap.session import Session

from taps import Line
from walk import Walk


class Vector:
    """Where each probe sits in a captured sample.

    A sample is one integer and the descriptor names it one bit at a
    time, in bit order, a bus as its own elements.  An element's place
    in that list is its weight, so a field is read back by gathering
    its bits in the order they were named.
    """

    def __init__(self, names):
        self.bits = {}
        for bit, name in enumerate(names):
            self.bits.setdefault(name.split("[")[0], []).append(bit)

    def get(self, sample, name):
        value = 0
        for weight, bit in enumerate(self.bits[name]):
            value |= ((sample >> bit) & 1) << weight

        return value


class Command:
    """One command slot, decoded the way the part decodes the pins."""

    # (ras_n, cas_n, we_n) with the chip selected.
    KIND = {
        (1, 1, 1): "NOP",
        (0, 1, 1): "ACT",
        (1, 0, 1): "RD",
        (1, 0, 0): "WR",
        (0, 1, 0): "PRE",
        (0, 0, 1): "REF",
        (0, 0, 0): "MRS",
        (1, 1, 0): "ZQC",
        }
    # Commands that carry a row, and commands that carry a column.  The
    # rest carry an address the part ignores, so printing it would be
    # printing whatever the idle encoding left on the pins.
    ROW = ("ACT",)
    COLUMN = ("RD", "WR")
    # Auto precharge rides the column address on this bit.
    AP_BIT = 10
    COLUMN_MASK = (1 << AP_BIT) - 1

    def __init__(self, vector, sample):
        self.deselected = vector.get(sample, "cs_n") == 1
        self.kind = self.KIND[(vector.get(sample, "ras_n"),
                               vector.get(sample, "cas_n"),
                               vector.get(sample, "we_n"))]
        self.bank = vector.get(sample, "bank")
        self.address = vector.get(sample, "address")

    @property
    def interesting(self):
        """Whether the slot said anything.  A deselected cycle is the
        bus idling, and a NOP is the part being told to do nothing:
        neither is a command a pass can be read by."""
        return not self.deselected and self.kind != "NOP"

    @property
    def column(self):
        return self.address & self.COLUMN_MASK

    @property
    def auto_precharge(self):
        return bool(self.address & (1 << self.AP_BIT))

    def text(self):
        if self.kind in self.ROW:
            return f"{self.kind:<3} bank {self.bank} row {self.address:#06x}"
        if self.kind in self.COLUMN:
            ap = " AP" if self.auto_precharge else ""
            return f"{self.kind:<3} bank {self.bank} col {self.column:#05x}{ap}"

        return f"{self.kind:<3} bank {self.bank}"


class Burst:
    """One controller cycle of the data bus, and where it belongs.

    The address is the one the command beside it carried, resolved
    against the row the bank had open, so a write and the read that
    fetches it back name the same place.

    A cycle on this part is sixteen bytes -- eight slots of two byte
    lanes, byte 2s + l being lane l of slot s -- so the unit every
    rotation and slide below is counted in is a byte and not a slot: a
    burst that came back a whole slot late is two bytes moved along.
    """

    BEATS = 16

    def __init__(self, cycle, data, place=None, command_cycle=None):
        self.cycle = cycle
        self.data = data
        self.place = place
        self.command_cycle = command_cycle

    @property
    def beats(self):
        return [(self.data >> (8 * i)) & 0xff for i in range(self.BEATS)]

    def text(self):
        return " ".join(f"{beat:02x}" for beat in self.beats)

    def rotation_of(self, other):
        """By how many bytes this burst is the other one turned round.

        The two directions are one rotation each: a burst that came
        back a byte late and one that came back a byte early differ
        only in which way the count runs, and both are reported as the
        distance that turns the write into the read.
        """
        mine, theirs = self.beats, other.beats
        for shift in range(1, self.BEATS):
            if mine == theirs[shift:] + theirs[:shift]:
                return shift

        return None

    def slide_of(self, other):
        """By how many bytes this burst is the other one moved along,
        without the bytes that fell off the end coming round.

        A burst sampled a byte late holds all but one of the write's
        bytes and one byte of whatever the bus held; a rotation would
        have put the last one back at the other end.
        """
        mine, theirs = self.beats, other.beats
        for shift in range(1, self.BEATS):
            if mine[shift:] == theirs[:-shift]:
                return shift
            if mine[:-shift] == theirs[shift:]:
                return -shift

        return None


class Pass:
    """One run of the walker, and the capture taken over it."""

    def __init__(self, index, errors, samples, vector):
        self.index = index
        self.errors = errors
        self.samples = samples
        self.vector = vector
        self.events = []
        self.writes = []
        self.reads = []
        self.counts = {}
        self.decode()

    def decode(self):
        """The capture as commands and bursts, in time order.

        Data and command are paired in issue order rather than by
        cycle: the DFI has the controller present write data on the
        cycle of its command and the PHY raise a valid when an answer
        comes back, so the n-th burst each way belongs to the n-th
        command of that kind.  Which cycles those were is kept, because
        the distance between them is half of what a wrong burst is
        read by.
        """
        open_row = {}
        commands = {"WR": [], "RD": []}
        bursts = {"WR": [], "RD": []}
        errors = 0

        for cycle, sample in enumerate(self.samples):
            command = Command(self.vector, sample)
            wrote = self.vector.get(sample, "wrdata_en")
            read = self.vector.get(sample, "rddata_valid")
            count = self.vector.get(sample, "error_count")

            if command.interesting:
                self.counts[command.kind] = self.counts.get(command.kind,
                                                            0) + 1
                if command.kind == "ACT":
                    open_row[command.bank] = command.address
                if command.kind in commands:
                    # The row as the bank held it when the command went
                    # out, not as the pass left it: a bank that is
                    # reactivated later would otherwise rename every
                    # place named before the change.
                    commands[command.kind].append(
                        (cycle, command, open_row.get(command.bank)))

            if wrote:
                bursts["WR"].append(Burst(cycle,
                                          self.vector.get(sample, "wrdata")))
            if read:
                bursts["RD"].append(Burst(cycle,
                                          self.vector.get(sample, "rddata")))

            beat = self.vector.get(sample, "r_beat")
            if command.interesting or wrote or read or beat or count != errors:
                self.events.append((cycle, command, wrote, read,
                                    count if count != errors else None, beat))
            errors = count

        for kind, out in (("WR", self.writes), ("RD", self.reads)):
            for burst, (cycle, command, row) in zip(bursts[kind],
                                                    commands[kind]):
                burst.command_cycle = cycle
                burst.place = (command.bank, row, command.column)
                out.append(burst)

    def spacing_text(self):
        """How close together the pass put its column commands.

        The distance between one column command and the next of the
        same kind is what a burst costs on the bus: the core spaces
        writes by the write latency the part is still serving and reads
        by the round trip to the PHY, so these two are the throughput
        the silicon reaches rather than the one a bench measured.
        """
        out = []
        for tag, bursts in (("wr", self.writes), ("rd", self.reads)):
            cycles = [burst.command_cycle for burst in bursts]
            gaps = [later - earlier
                    for earlier, later in zip(cycles, cycles[1:])]
            if not gaps:
                continue

            tally = {}
            for gap in gaps:
                tally[gap] = tally.get(gap, 0) + 1
            spread = " ".join(f"{count}x{gap}"
                              for gap, count in sorted(tally.items()))
            out.append(f"{tag} {min(gaps)}..{max(gaps)} cycles apart"
                       f" ({spread})")

        return ", ".join(out)

    def count_text(self):
        """What the pass put on the command pins, by kind.

        A refresh falling inside a pass is what the window is watched
        for, and it is the one command a walker never asks for.
        """
        return " ".join(f"{kind.lower()} {self.counts[kind]}"
                        for kind in sorted(self.counts))

    def render(self):
        print(f"--- pass {self.index}, {self.errors} bad beats,"
              f" {len(self.writes)} write bursts, {len(self.reads)} read"
              f" bursts")
        print("  cycle | command                | write burst"
              "             | read burst")
        for cycle, command, wrote, read, count, beat in self.events:
            text = command.text() if command.interesting else ""
            write = self.burst_at(self.writes, cycle) if wrote else ""
            answer = self.burst_at(self.reads, cycle) if read else ""
            tail = []
            if count is not None:
                tail.append(f"errors {count}")
            if beat:
                tail.append("r beat")
            note = ("  " + ", ".join(tail)) if tail else ""
            print(f"  {cycle:>5} | {text:<22} | {write:<23} |"
                  f" {answer:<23}{note}")

    @staticmethod
    def burst_at(bursts, cycle):
        for burst in bursts:
            if burst.cycle == cycle:
                return burst.text()

        return ""

    def written_at(self, place):
        for burst in self.writes:
            if burst.place == place:
                return burst

        return None


class Trace:
    DEPTH = 1024
    OFFSET = Walk.OFFSET
    TAP = Walk.TAP
    PASSES = 40
    POLL_SECONDS = 0.05
    PASS_TIMEOUT = 30.0
    CAPTURE_TIMEOUT = 5.0

    def __init__(self, path, passes=PASSES, size=Walk.PROBE, pre=None,
                 offset=OFFSET, tap=TAP):
        self.session = Session(path)
        self.passes = passes
        self.size = size
        self.pre = pre
        self.offset = offset
        self.tap = tap
        self.panel = None
        self.control = None
        self.trigger = None
        self.buffer = None
        self.vector = None
        self.trigger_bit = None
        self.trigger_name = None
        self.depth = self.DEPTH

    @staticmethod
    def parse(args):
        path = Walk.DEFAULT_PATH
        passes = Trace.PASSES
        size = Walk.PROBE
        pre = None
        offset, tap = Trace.OFFSET, Trace.TAP
        for arg in args:
            key, sep, value = arg.partition("=")
            if sep and key == "passes":
                passes = int(value, 0)
            elif sep and key == "size":
                size = int(value, 0)
            elif sep and key == "pre":
                pre = int(value, 0)
            elif sep and key == "offset":
                offset = int(value, 0)
            elif sep and key == "tap":
                tap = int(value, 0)
            elif not sep:
                path = arg

        return path, passes, size, pre, offset, tap

    # -- the bench ---------------------------------------------------------

    async def setup(self):
        """The board record on the panel, with the read path at the
        centre of the mapped eye.

        Set here rather than left wherever another script put it, so a
        pass captured here is a pass at the settings the maps measured
        and not at whatever the last run ended on.
        """
        for name in ("run", "level", "mpr", "poke", "tdqs", "snoop"):
            await self.panel.control_write(name, 0)
        # The capture is taken at one named point of the read plane, so
        # the panel's copy of the record is what the PHY reads here.
        await Walk.take_panel(self.panel, offset=self.offset)
        await self.panel.control_write("poke_ap", 0)
        await self.panel.control_write("odt", 1)

        line = Line(self.panel)
        if not await line.goto(self.tap):
            print("the delay lines never reported their shortest tap")
            return False

        print(f"read path at offset {self.offset}, tap {self.tap}")
        return True

    def capture_blocks(self):
        """The capture core's three blocks, by the name the analyzer's
        domain gives them."""
        control = None
        for name in ("capture.ram.control", "ram.control"):
            try:
                control = self.session.block_by_name(name)
                break
            except KeyError:
                continue

        if control is None:
            raise SystemExit("no capture control block in the rack")

        return control, control.trigger_node_get(), control.sink_node_get()

    async def arm(self):
        """A window over the part of the pass that can be read.

        A region the window holds whole is caught from its first cycle:
        the run is down when this is called, so a match on it fires as
        the host raises it.  A region longer than the window has its
        reads thousands of cycles past its writes, and the cycle worth
        holding is then the one a beat came back wrong on, so the
        trigger is the walker's own error and the window sits mostly
        before it.
        """
        await self.trigger.configure(value=1 << self.trigger_bit,
                                     mask=1 << self.trigger_bit)
        await self.control.configure(self.depth, self.pre_trigger())
        await self.control.arm()

    def pre_trigger(self):
        """How much of the window stands before the trigger.

        None of it on the run, which begins a pass; all but a burst's
        own answer on an error, since what names a bad beat is the
        commands that led to it.
        """
        if self.pre is not None:
            return self.pre
        if self.trigger_name == "run":
            return 0

        return self.depth - 64

    async def wait_idle(self):
        start = time.monotonic()
        while time.monotonic() - start < self.CAPTURE_TIMEOUT:
            state, triggered, _ = await self.control.status()
            if state == self.control.STATE_IDLE:
                return triggered
            await asyncio.sleep(self.POLL_SECONDS)

        await self.control.abort()
        return None

    async def one_pass(self, index):
        """One pass of the probe walker with a window over it.

        The walker is selected with the run down: it is held in reset
        by the run and by the selection together, so choosing it while
        the run is up releases it for a whole host round trip before
        the run proper starts -- and that traffic would be the first
        thing in the window.
        """
        await self.panel.control_write("run", 0)
        await self.panel.control_write("full", self.size)
        await self.arm()
        await self.panel.control_write("run", 1)

        start = time.monotonic()
        while not await self.panel.status_read("done"):
            if time.monotonic() - start > self.PASS_TIMEOUT:
                await self.panel.control_write("run", 0)
                await self.control.abort()
                return None
            await asyncio.sleep(self.POLL_SECONDS)

        errors = await self.panel.status_read("error_count")
        if self.trigger_name == "error" and not errors:
            # Nothing fired the window and nothing was going to, so the
            # capture is taken down here rather than waited out.
            await self.control.abort()
            await self.panel.control_write("run", 0)
            print(f"pass {index}: no bad beat")
            return None

        triggered = await self.wait_idle()
        if triggered is None:
            print(f"pass {index}: the capture never returned to idle")
            await self.panel.control_write("run", 0)
            return None

        head = await self.control.head(0)
        samples = await self.buffer.read_window(head, self.depth,
                                                self.control.signal_count)
        await self.panel.control_write("run", 0)

        if not triggered:
            print(f"pass {index}: the capture never fired on"
                  f" {self.trigger_name}")
            return None

        return Pass(index, errors, samples, self.vector)

    # -- reading a pass back -----------------------------------------------

    @staticmethod
    def elsewhere(read, one):
        """Another burst of the same pass holding what came back.

        The walker writes the same payload to the same address every
        pass, so a read answering with the previous pass's write to its
        own address is a read that cannot be told from a good one.  A
        read answering with a *neighbour's* payload can, and that is
        the stale answer this bench is able to see.
        """
        for burst in one.writes:
            if burst.place != read.place and burst.data == read.data:
                bank, row, column = burst.place
                row_text = "?" if row is None else f"{row:#06x}"
                return f"bank {bank} row {row_text} col {column:#05x}"

        return None

    @staticmethod
    def classify(read, written, earlier):
        """What a read burst is, against the write to its own address.

        The four answers are the four things a burst that came back
        wrong can be, and they point at different parts of the path: a
        rotation or a slide is the burst arriving beside the window it
        was sampled in, the earlier pass's payload is a read that never
        reached the array, and anything else is a bus that was not
        carrying a burst at all.
        """
        if written is None:
            return "unpaired"
        if read.data == written.data:
            return "same"

        rotation = read.rotation_of(written)
        if rotation is not None:
            return f"shifted by {rotation} bytes"

        slide = read.slide_of(written)
        if slide is not None:
            return f"shifted by {abs(slide)} bytes"

        if earlier is not None and read.data == earlier.data:
            return "previous"

        return "other"

    @classmethod
    def pair(cls, one, before):
        print(f"--- pass {one.index}, read bursts against the writes of the"
              " same pass")
        print("  place                    | write burst             |"
              " read burst              | cycles | what")
        for read in one.reads:
            written = one.written_at(read.place)
            earlier = before.written_at(read.place) if before else None
            bank, row, column = read.place
            row_text = "?" if row is None else f"{row:#06x}"
            place = f"bank {bank} row {row_text} col {column:#05x}"
            write_text = written.text() if written else "-"
            distance = ("-" if written is None
                        else str(read.command_cycle - written.command_cycle))
            what = cls.classify(read, written, earlier)
            other = cls.elsewhere(read, one) if what == "other" else None
            if other is not None:
                what = f"other, the payload of {other}"
            print(f"  {place:<24} | {write_text:<23} | {read.text():<23} |"
                  f" {distance:>6} | {what}")

    # -- the run -----------------------------------------------------------

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        if not await self.panel.status_read("ready"):
            print("controller: not ready, the power-up sequence has not run")
            return 1

        self.control, self.trigger, self.buffer = self.capture_blocks()
        self.vector = Vector(self.control.signal_names)
        # The probe's whole pass fits the window; the larger regions
        # read back thousands of cycles after they were written, so
        # only the cycle a beat came back wrong on can place a window
        # on them.
        self.trigger_name = "run" if self.size == Walk.PROBE else "error"
        self.trigger_bit = self.trigger.signal_names.index(self.trigger_name)
        # The core's own cap, which its capture-length register is sized
        # from: a window longer than the buffer holds is refused.
        self.depth = min(self.DEPTH, self.control.max_samples())
        print(f"capture: {self.control.signal_count} probes,"
              f" {self.buffer.depth} samples deep,"
              f" {self.control.sample_rate} Hz")
        print(f"walking {Walk.SIZE_NAME[self.size]}, triggering on"
              f" {self.trigger_name}, {self.pre_trigger()} samples before it")

        if not await self.setup():
            return 1

        clean, failing = None, None
        for index in range(self.passes):
            one = await self.one_pass(index)
            if one is None:
                continue

            print(f"pass {index}: {one.errors} bad beats,"
                  f" {one.count_text()}")
            print(f"         {one.spacing_text()}")
            if one.errors:
                failing = one
                break
            clean = one

        await self.panel.control_write("run", 0)

        if failing is None:
            print(f"no pass of {self.passes} came back with errors")
            if clean is not None:
                clean.render()
                self.pair(clean, None)
            await Walk.leave_panel(self.panel)
            return 1

        if clean is not None:
            clean.render()
            self.pair(clean, None)

        failing.render()
        self.pair(failing, clean)
        await Walk.leave_panel(self.panel)
        return 0


async def main():
    got = Trace.parse(sys.argv[1:])
    if await Trace(*got).run():
        raise SystemExit(1)
