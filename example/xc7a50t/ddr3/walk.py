"""Walk a region of the DDR3 part, at the settings the design carries.

Run with::

  acrobe run walk.py [resource-path] [dqs-invert] [size=0..3] [count=N]
                     [train=1]

The size says which region is walked: zero is the 128 byte probe the
map uses, one the whole part, two every bank at row zero and three that
with a second row on top.  The default is the whole part.

``count=N`` runs the region N times, one walk after another out of one
session.  One session on purpose: a script killed inside a transfer
keeps the FTDI interface, and the next process waits on it forever
without printing a line, which reads exactly like a dead design.

By default nothing is trained.  The read offset, the tap of the delay
line, the whole-word slip of the write and the lead of each pad's
enable are a board record the design was built with, and the PHY
applies them itself at reset: a walk then says whether that record is
right, which is the question a design has, rather than whether a search
can be made to converge.

``train=1`` maps the read plane first and leaves the read path where
the map says, which is how the record's two read figures were found in
the first place.  A point answering says nothing about what sits either
side of it, and where the first one lands moves from run to run, so the
whole plane is mapped -- every offset the part can answer at, at every
tap of the line, one pass of the probe walker each -- and the read path
is left in the middle of the widest run of clean taps, preferring a run
that ends inside the line to one an end of the line cuts short.
``readmap.py`` says how that plane is read.
"""

import asyncio
import pathlib
import re
import sys
import time

from acrobe_plugin.gatecap.session import Session

from readmap import Line, Probe


class Walk:
    # The tap answers out of the fabric rather than out of the JTAG
    # shifter, so the adapter's own clock has to be slowed to something
    # the logic behind it keeps up with.  Left at its default the
    # transport never converges.
    DEFAULT_PATH = ("hs2-/jtag(fmax=20M)/chain/0"
                    "/bnoc_continuous_transport/gatecap")

    # The regions the panel carries.  A contiguous region cannot reach
    # a second row without having crossed every bank boundary first --
    # the bank bits sit below the row bits in the core's address map --
    # so the ladder between the probe and the whole part is a bank
    # crossing, then a row crossing on top of it.
    PROBE = 0
    WHOLE = 1
    BANKS = 2
    ROWS = 3

    SIZE_NAME = {
        PROBE: "the 128 byte probe",
        WHOLE: "the whole part, 128 MiB",
        BANKS: "every bank at row zero, 8 KiB",
        ROWS: "two rows in every bank, 16 KiB",
        }

    # What the panel counts on the bus the selected walker drives, and
    # what the core put on the command pins.  Printed in this order, so
    # a stall reads as the place the movement stops.
    AXI_COUNTERS = (("aw", "aw_count"), ("w", "w_count"), ("b", "b_count"),
                    ("ar", "ar_count"), ("r", "read_count"))
    DFI_COUNTERS = (("act", "act_count"), ("pre", "pre_count"),
                    ("wr", "wr_count"), ("rd", "rd_count"),
                    ("ref", "ref_count"), ("mrs", "mrs_count"))

    # Both sides of every channel, in the order the panel packs them.
    CHANNELS = ("aw", "w", "b", "ar", "r")

    TOLERANCE_PPM = 200
    # The walk runs by itself once the run bit is up and the host only
    # asks whether it is over, so how often it asks is the resolution
    # of the time it reports.  A whole-part walk is over in a second or
    # so and a fifth of that would be visible in the figure.
    POLL_SECONDS = 0.02
    # A pass of the short walker is over in microseconds, so anything
    # past this is a pass that will not end.
    PROBE_SECONDS = 5.0
    # The cap on a measured walk.  A script killed in the middle of a
    # transaction wedges the transport until the part is programmed
    # again, so a run that will not finish has to be one the script
    # stops waiting for rather than one an operator interrupts.
    RUN_SECONDS = 300.0
    REPORT_SECONDS = 1.0
    # What a sweep of the panel's two read knobs runs to: every offset
    # the capture can be placed at, and more delay steps than any line
    # on this family carries, so a run of that many returns the line to
    # where it started.
    OFFSET_COUNT = 128
    TAP_COUNT = 64
    # A window narrower than this is an edge and not a place to sit,
    # wherever on the plane it was found.
    EYE_MINIMUM = 4

    # The board record, repeated from src/boundary.vhd.  The design
    # carries it and the PHY applies it; these are here so that an
    # instrument sweeping one of them can put the other four back where
    # the record leaves them, and so that a script can say what it is
    # measuring against.
    #
    # Slots from a read's announcement to its first beat, and the tap
    # of the delay line every data pin is sampled through: the map
    # below is what found them.
    OFFSET = 53
    TAP = 13
    # Where the data sits against the strobe, in whole slots, against a
    # nominal of eight: the ruler measured this board's burst leaving a
    # whole controller cycle ahead of its own strobe, and zero is the
    # slip that puts it back.
    SLIP = 0
    # Slips the panel carries: a whole word either way of the nominal.
    SLIP_COUNT = 16
    # Slots the family puts a data pad's tristate word on the pin ahead
    # of its data word: measured by the drive map.
    DQ_LEAD = 6
    # The same for the strobe pad, which is serialised on the other
    # clock: measured by the drive map.
    DQS_LEAD = 14
    # Which way round the strobe pattern leaves.  Zero is the pattern
    # the schedule holds; one turns it round, for a board that presents
    # the pair the other way about.
    DQS_INVERT = 0

    @staticmethod
    async def take_panel(panel, offset=OFFSET, slip=SLIP, dq_lead=DQ_LEAD,
                         dqs_lead=DQS_LEAD, invert=DQS_INVERT):
        """Put the panel's own copy of the record on the PHY.

        The PHY reads the record straight out of the design while the
        manual bit is low, which is where a board with no host attached
        leaves it.  A script that means to move one of these five says
        so by writing all five and raising that bit, so what it sweeps
        moves against a rest that is known and not against whatever a
        register happened to come out of reset at.
        """
        await panel.control_write("offset", offset)
        await panel.control_write("slip", slip)
        await panel.control_write("dq_lead", dq_lead)
        await panel.control_write("dqs_lead", dqs_lead)
        await panel.control_write("dqs_invert", invert)
        await panel.control_write("manual", 1)

    @classmethod
    async def leave_panel(cls, panel):
        """Hand the PHY back to the record the design carries.

        The delay lines are walked back to the record's tap on the way.
        Dropping the bit cannot do it: the PHY places them once at
        reset and nothing outside it places them again, so a script
        that has moved them has to put them back or the next reader
        measures where that script stopped.
        """
        await Line(panel).goto(cls.TAP)
        await panel.control_write("manual", 0)

    @staticmethod
    def parse(args):
        """The resource path and the strobe sense, in either order.

        A bare number is the sense, a name=value pair is an option read
        elsewhere, and anything else is the path, so none of them has
        to be spelled out to give another.
        """
        path = Walk.DEFAULT_PATH
        invert = Walk.DQS_INVERT
        for arg in args:
            if "=" in arg:
                continue
            if arg.isdigit():
                invert = int(arg)
            else:
                path = arg
        return path, invert

    @staticmethod
    def option(args, name, default):
        """A name=value argument, as an integer."""
        for arg in args:
            key, _, value = arg.partition("=")
            if key == name:
                return int(value, 0)

        return default

    def __init__(self, path, invert=DQS_INVERT, size=WHOLE, train=False,
                 count=1):
        self.session = Session(path)
        self.invert = invert
        self.size = size
        self.train_first = train
        self.count = count
        self.ram_hz = self.built_for_hz()
        self.panel = None
        self.line = None

    @staticmethod
    def built_for_hz():
        """The memory rate the bitstream was built for.

        Read from the design rather than repeated here, so the two
        cannot drift while the rate is being changed.
        """
        source = pathlib.Path(__file__).with_name("src") / "boundary.vhd"
        text = source.read_text()
        fast = re.search(r"constant\s+fast_hz_c\s*:\s*natural\s*:=\s*(\d+)",
                         text)
        if not fast:
            raise SystemExit(f"no fast_hz_c in {source}")

        return int(fast.group(1)) // 4

    async def clock_ok(self):
        # The measurer counts over a second of its reference, so a
        # reading taken straight after configuration is a part-counted
        # one.  Give it a few refreshes before believing it.
        got = None
        for _ in range(5):
            rates = await self.session.block_by_name("rates").rates()
            got = rates.get("ram")
            if got is not None and abs(got - self.ram_hz) <= (
                    self.ram_hz * self.TOLERANCE_PPM / 1e6):
                break
            await asyncio.sleep(1.0)

        if got is None:
            print("ram: absent from the rack")
            return False

        ppm = (got - self.ram_hz) / self.ram_hz * 1e6
        ok = abs(ppm) <= self.TOLERANCE_PPM
        print(f"ram clock: {got:>11} Hz  want {self.ram_hz:>11} Hz"
              f"  {ppm:+8.1f} ppm  {'ok' if ok else 'BAD'}")
        if not ok:
            print("  a memory clock that is not the one the controller was "
                  "built for makes every timing below meaningless")
        return ok

    async def counters(self):
        """Every counter the panel carries, in one reading."""
        got = {}
        for _, name in self.AXI_COUNTERS + self.DFI_COUNTERS:
            got[name] = await self.panel.status_read(name)
        for name in ("last_aw", "last_ar", "handshake"):
            got[name] = await self.panel.status_read(name)

        return got

    @classmethod
    def handshake_line(cls, word):
        """Which side of which channel is waiting, right now.

        A channel reads ``-`` for a side that is not asserted, so a
        stalled bus shows one letter standing alone: the side that is
        offering, against a side that never answers.
        """
        out = []
        for index, name in enumerate(cls.CHANNELS):
            valid = (word >> (2 * index)) & 1
            ready = (word >> (2 * index + 1)) & 1
            out.append(f"{name}{'V' if valid else '-'}{'R' if ready else '-'}")

        return " ".join(out)

    @classmethod
    def counter_line(cls, seconds, busy, done, got):
        axi = " ".join(f"{tag} {got[name]}" for tag, name in cls.AXI_COUNTERS)
        dfi = " ".join(f"{tag} {got[name]}" for tag, name in cls.DFI_COUNTERS)
        return (f"{seconds:5.0f}s  busy {busy} done {done}"
                f"  | {axi}"
                f"  | last aw {got['last_aw']:#x} ar {got['last_ar']:#x}"
                f"  | {dfi}"
                f"  | {cls.handshake_line(got['handshake'])}")

    async def report(self, seconds, got=None):
        """One line of where the run has got to."""
        busy = await self.panel.status_read("busy")
        done = await self.panel.status_read("done")
        if got is None:
            got = await self.counters()
        print(self.counter_line(seconds, busy, done, got))

    async def run_once(self, size, timeout=PROBE_SECONDS, watch=False):
        """Take one walker through a pass, or give up waiting on it.

        Returns the error count, or None for a run that never said it
        was done: the wait has to end by itself, because a script
        killed in the middle of a transaction wedges the transport.
        """
        # Selected with the run down, and not the other way about: a
        # walker is held in reset by the run bit and by the selection
        # together, so choosing one while the run is still up releases
        # it at once and it drives the bus for a whole host round trip
        # before the run proper starts.
        #
        # The adapter and the core leave reset with the walker, so the
        # part's power-up sequence runs at the front of every pass and
        # nothing the walker offers is taken until that is over.  It is
        # under a millisecond against a whole-part walk of three
        # quarters of a second, and it is what makes a pass start from
        # the state the benches cover.
        await self.panel.control_write("run", 0)
        await self.panel.control_write("full", size)
        await self.panel.control_write("run", 1)

        start = time.monotonic()
        due = 0.0
        while not await self.panel.status_read("done"):
            now = time.monotonic() - start
            if watch and now >= due:
                await self.report(now)
                due = now + self.REPORT_SECONDS
            if now > timeout:
                return None
            await asyncio.sleep(self.POLL_SECONDS)

        return await self.panel.status_read("error_count")

    async def walk(self, size):
        """One measured pass, with what the bus did while it ran."""
        print(f"--- walking {self.SIZE_NAME[size]}")
        start = time.monotonic()
        errors = await self.run_once(size, timeout=self.RUN_SECONDS,
                                     watch=True)
        elapsed = time.monotonic() - start
        got = await self.counters()
        await self.report(elapsed, got)
        first = await self.panel.status_read("first_error_address")

        if errors is None:
            print(f"walk: still busy after {self.RUN_SECONDS:.0f} s;"
                  " the line above is where it stopped")
            print("STALLED")
            return 1

        if errors:
            print(f"walk: {errors} bad beats, first at byte {first:#x}")
            print("FAILED")
            return 1

        print("walk: every location written and read back")
        self.throughput(elapsed, got)
        print("PASSED")
        return 0

    def throughput(self, elapsed, got):
        """What the walk cost, in time and in controller cycles.

        The walk runs on the controller clock with no host in it, so
        the wall time is the run time and the rate that clock was
        checked at turns it into cycles.  Every transaction is written
        and read back, so the figure below covers both halves of one.
        """
        cycles = elapsed * self.ram_hz
        print(f"walk: {elapsed:.2f} s to done,"
              f" about {cycles / 1e6:.1f}M controller cycles")
        if got["aw_count"]:
            print(f"  {cycles / got['aw_count']:.1f} cycles a transaction,"
                  f" written and read back,"
                  f" over {got['aw_count']} of them")

    async def report_silence(self):
        """What the bus did, for a sweep that found nothing.

        A part that is not driving the bus at all and one driving it at
        the wrong moment read the same through an error count, and
        differently here.
        """
        low = await self.panel.status_read("first_read_low")
        high = await self.panel.status_read("first_read_high")
        first = (high << 32) | low
        beats = await self.panel.status_read("read_count")
        print(f"  beats returned: {beats}")
        print(f"  first beat read: {first:#018x}")
        if first in (0, (1 << 64) - 1):
            print("  a beat of all ones or all zeroes is a bus nobody drove:"
                  " look at the strobe and the command pins before the"
                  " capture")
        else:
            print("  the part is driving; what is wrong is when it is"
                  " sampled")

    async def train(self):
        """Map the read plane, and sit in the middle of its widest run.

        The map is the whole of the choice: what the read path is left
        at is a position on the line the sweep measured, not a count of
        steps from wherever it stopped.
        """
        probe = Probe(self.panel, self.PROBE)
        table = probe.table()
        await table.fill(self.line, probe.cell)
        table.summarise()

        offset, tap, width, touches = table.choose()
        if offset is None:
            print("no offset and delay bring a burst back whole")
            await self.report_silence()
            return False

        if touches:
            print("  every clean run reaches an end of the delay line, where"
                  " the line stops rather than the window: the widest of them"
                  " is as much as this can see")
        print(f"read answers at offset {offset}, over {width} taps of the"
              f" line; the middle of that run is tap {tap}")
        if width < self.EYE_MINIMUM:
            print(f"  {width} taps is an edge and not a window; the read path"
                  " is marginal wherever it is left")

        if not await self.line.goto(tap):
            print("the delay lines never reported their shortest tap:"
                  " the read path is left wherever the sweep ended")
            return False

        await self.panel.control_write("offset", offset)
        return True

    async def run(self):
        await self.session.open()

        if not await self.clock_ok():
            return 1

        self.panel = self.session.block_by_name("panel")
        self.line = Line(self.panel)

        # The run is raised before anything drops it, and that is not
        # redundant.  What a control register holds straight after
        # configuration is a property of the family -- zero on this
        # one, one on the Lattice part the SDRAM bench runs on -- and a
        # session that drops a bit already down resets nothing: the
        # first pass is then a reading of a walker that has been
        # running since the clock did.  One raise makes the drop that
        # follows a transition either way, and a transition is what
        # resets anything.
        await self.panel.control_write("run", 1)
        await self.panel.control_write("run", 0)

        if not await self.panel.status_read("ready"):
            print("controller: not ready, the power-up sequence has not run")
            return 1

        # Nothing in the sequencer is to own the bus, and the walker's
        # own reads are what answers rather than a snooped write.
        await self.panel.control_write("snoop", 0)
        await self.panel.control_write("mpr", 0)
        await self.panel.control_write("level", 0)
        # Nothing on the board terminates the part's receivers and the
        # controller never asks it to, so this does.
        await self.panel.control_write("odt", 1)

        if self.train_first:
            # The map moves the delay line and the read offset, so the
            # panel's copy of the record is what the PHY reads while it
            # runs.  The three the map does not touch go with it.
            await self.take_panel(self.panel, invert=self.invert)
            if not await self.train():
                return 1
        elif self.invert != self.DQS_INVERT:
            # The other way round is not what the record says, so it
            # has to go through the panel.
            await self.take_panel(self.panel, invert=self.invert)
            print(f"at the board record but for the strobe sense:"
                  f" invert {self.invert}")
        else:
            # Straight to the record, without walking the delay lines:
            # they are where the PHY placed them, and a walk of them
            # here would hide a script that had left them elsewhere.
            await self.panel.control_write("manual", 0)
            print(f"at the board record: offset {self.OFFSET},"
                  f" tap {self.TAP}, slip {self.SLIP},"
                  f" leads {self.DQ_LEAD}/{self.DQS_LEAD},"
                  f" invert {self.DQS_INVERT}")
            if not await self.at_record():
                return 1

        bad = 0
        for index in range(1, self.count + 1):
            if self.count > 1:
                print(f"--- pass {index} of {self.count}")
            bad += await self.walk(self.size)

        if self.count > 1:
            print(f"--- {self.count - bad} of {self.count} walks clean")

        return 1 if bad else 0

    async def at_record(self):
        """Whether the delay lines are still where the PHY placed them.

        The lines come up at the record's tap and nothing but a script
        moves them, so a mark at this point says one has been walked
        round since the design was configured -- in which case the tap
        is wherever that script stopped, and a walk from here measures
        that and not the record.
        """
        if self.TAP and await self.line.home():
            print("the delay lines are at their mark rather than at the"
                  f" record's tap {self.TAP}: something has walked them"
                  " since the part was configured, so program it again"
                  " before believing this")
            return False

        return True


async def main():
    path, invert = Walk.parse(sys.argv[1:])
    size = Walk.option(sys.argv[1:], "size", Walk.WHOLE)
    train = Walk.option(sys.argv[1:], "train", 0)
    count = Walk.option(sys.argv[1:], "count", 1)
    if await Walk(path, invert, size, bool(train), count).run():
        raise SystemExit(1)
