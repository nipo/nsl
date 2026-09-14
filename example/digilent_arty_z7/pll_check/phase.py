"""Measure the phase between the four shifted clocks.

Run with::

  acrobe run phase.py [resource-path]

The four outputs run at 12 MHz and are sampled, raw, by an 87.5 MHz
clock from the other block.  The two rates are 175 over 24 in lowest
terms, so the sampling instant lands on 175 distinct points of the
12 MHz cycle before repeating: an edge resolves to a 175th of a
cycle, a shade over two degrees.

Rather than hunting edges, every sample is given the phase of the
cycle it was taken at and summed as a unit vector.  The argument of
that sum moves with the clock's own phase and with nothing else, so
the difference between two channels is the shift between them -- duty
cycle, capture length and where the trigger fired all cancel.
"""

import cmath
import math
import sys

from acrobe_plugin.gatecap.session import Session


class PhaseCheck:
    DEFAULT_PATH = ("dig-003017a4c9e1/jtag/chain/0"
                    "/bnoc_continuous_transport/gatecap")

    # Sampling rate over output rate, exactly, as the solver built
    # them: 1050/12 MHz over 900/75 MHz.
    SAMPLE_HZ = 87_500_000
    OUTPUT_HZ = 12_000_000

    # Channels in the order the description lists them, which is the
    # order of the bits of a sample, and what each should measure.
    CHANNELS = [("p0", 0.0), ("p90", 90.0), ("p180", 180.0), ("p270", 270.0)]

    # A tenth of the step being measured.  Routing from the global
    # buffer to the capture flip-flop differs per channel by a
    # nanosecond or so, which at 12 MHz is a few degrees.
    TOLERANCE_DEG = 9.0

    SAMPLE_COUNT = 4096

    def __init__(self, path):
        self.session = Session(path)

    @staticmethod
    def bit(sample, index):
        return (sample >> index) & 1

    def sample_phase(self, n):
        """Phase of sample n within the output cycle, in turns."""
        return (n * self.OUTPUT_HZ / self.SAMPLE_HZ) % 1.0

    async def capture(self):
        control = self.session.block_by_name("phases.sample.control")
        trigger = control.trigger_node_get()
        sink = control.sink_node_get()

        # Match anything: the capture is a plain window, the trigger
        # instant carries no meaning here.  An edge trigger compares
        # the new sample and the previous one, so it takes two pairs.
        await trigger.configure(0, 0, 0, 0)
        await control.configure(length=self.SAMPLE_COUNT)
        await control.arm()
        triggered, _done = await control.wait_done()
        if not triggered:
            raise SystemExit("capture never triggered")
        head = await control.head(0)
        return await sink.read_window(head, self.SAMPLE_COUNT,
                                      control.signal_count)

    def phases_of(self, samples):
        """Argument of the first harmonic of every channel, in turns."""
        out = []
        for index in range(len(self.CHANNELS)):
            acc = 0j
            high = 0
            for n, sample in enumerate(samples):
                if self.bit(sample, index):
                    acc += cmath.exp(-2j * math.pi * self.sample_phase(n))
                    high += 1
            duty = high / len(samples)
            # The sum points against the phase, hence the negation.
            out.append(((-cmath.phase(acc) / (2 * math.pi)) % 1.0, duty))
        return out

    async def run(self):
        await self.session.open()
        samples = await self.capture()

        measured = self.phases_of(samples)
        reference = measured[0][0]

        bad = 0
        for (name, want), (turns, duty) in zip(self.CHANNELS, measured):
            got = ((turns - reference) % 1.0) * 360.0
            error = (got - want + 180.0) % 360.0 - 180.0
            ok = abs(error) <= self.TOLERANCE_DEG
            print(f"{name:>5}: {got:7.2f} deg  want {want:6.1f}"
                  f"  {error:+6.2f}  duty {duty:.3f}  {'ok' if ok else 'BAD'}")
            if not ok:
                bad += 1

        if bad:
            print("FAILED: a shift is not where the library says it is.")
            print("Read the order: phases coming out descending means the"
                  " block advances where the library promises a delay.")
        else:
            print("PASSED")
        return bad


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else PhaseCheck.DEFAULT_PATH
    if await PhaseCheck(path).run():
        raise SystemExit(1)
