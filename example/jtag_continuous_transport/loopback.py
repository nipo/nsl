#!/usr/bin/env python3
"""Loopback driver for the continuous-transport demo platform.

The GHDL ``simulator.exe`` (see ``readme.rst``) exposes both ends of one
``nsl_jtag.continuous_transport`` link as TCP sockets:

* ``:4242`` — ATE side: the JTAG transactor command/response stream,
  HDLC-framed. We drive it with acrobe's ``continuous_transport`` host
  driver, layered on a TAP discovered over the transactor.
* ``:4243`` — application side: whatever crosses the transport surfaces
  here as HDLC-framed app bytes, and vice versa.

Connecting to *both* sockets turns the single simulated link into a
loopback we can test end to end: data pushed through the driver (TDI)
surfaces on ``:4243``; data pushed into ``:4243`` comes back through the
driver (TDO).

Everything below the driver is reusable acrobe (TCP pipe, HDLC framing,
the continuous-transport datagram). The only test-bench-specific glue is
wiring the acrobe ``JtagTransactor`` *codec* onto an HDLC datagram as a
``JtagInterface`` — that is what ``framed_ate`` speaks on ``:4242`` — and
knowing that USER0 (IR ``0x8``) selects the transport's data register.

Run the simulator first, then::

    ./simulator.exe &
    python3 loopback.py
"""

from __future__ import annotations

import argparse
import asyncio

from acrobe import lifecycle
from acrobe.root import root
from acrobe.adapter.model import make_hw_root
from acrobe.protocol.datagram import Datagram
from acrobe.protocol.jtag import JtagInterface
from acrobe.component.nsl.jtag_continuous_transport import ContinuousTransport
from acrobe.component.nsl.transactor.jtag import JtagTransactor
from acrobe.util.endian import swib

# Parameters of the simulated TAP (readme.rst / tb.vhd).
USER0_IR = 0x8          # selects continuous_transport reg_id_c = 1
SIM_BASE_FREQ = 1e6     # nominal; the simulator ignores the TCK divisor


class JtagTransactorInterface(JtagInterface):
    """Test-bench glue: NSL JTAG transactor over a framed datagram.

    Drives the ``nsl_jtag.transactor.framed_ate`` on ``:4242``. Each
    bit-level JTAG batch is encoded to one transactor command frame,
    sent as one datagram, and its response frame decoded back into the
    batch's op futures. This wiring is specific to how the demo exposes
    JTAG (a framed transactor over HDLC), hence it lives with the tb.
    """

    def __init__(self, datagram: Datagram, base_freq: float = SIM_BASE_FREQ,
                 name: str = "jtag"):
        super().__init__(name=name)
        self._dg = datagram
        self._codec = JtagTransactor(base_freq)
        self._lock = asyncio.Lock()

    def freq_update(self, freq):
        return self._codec.freq_update(freq)

    async def flush_ops(self, batch):
        try:
            cmd, _rsp_size, gather = self._codec.encode(batch)
        except Exception as exc:
            for _op, future in batch:
                if not future.done():
                    future.set_exception(exc)
            return
        try:
            async with self._lock:
                await self._dg.send(cmd)
                rsp, _ctx = await self._dg.recv()
        except Exception as exc:
            for _op, future in batch:
                if not future.done():
                    future.set_exception(exc)
            return
        self._codec.decode(batch, rsp, gather)


async def _open_ate(hw, host, port) -> ContinuousTransport:
    """Resolve the ATE-side path to the TAP and attach the driver."""
    transactor_route = await root(f"tcp/{host}:{port}/hdlc/addr0")
    ate = JtagTransactorInterface(transactor_route, 20e6)
    transactor_route.child_add(ate)
    await asyncio.sleep(0)
    chain = await ate.child_summon("chain")
    tap, = chain.children
    transport = ContinuousTransport(tap, USER0_IR)
    tap.child_add(transport)
    return transport


async def _open_app(hw, host, port) -> Datagram:
    """Resolve the application-side path to a plain framed datagram."""
    loopback_route = await root(f"tcp/{host}:{port}/hdlc/addr0")
    return loopback_route

async def _check(label, sender, receiver, payload):
    await sender.send(payload)
    got, _ctx = await receiver.recv()
    ok = got == payload
    print(f"  [{'ok' if ok else 'FAIL'}] {label}: {len(payload)} bytes")
    if not ok:
        raise AssertionError(
            f"{label}: sent {payload.hex()}, got {got.hex()}")

async def ate_to_app(app, ate, size):
    # swib() maps one input in 1..512 to 0; the transport has no
    # zero-byte frame, so skip that case.
    if not size:
        return
    payload = bytes((x & 0xff) for x in range(size))
    await asyncio.wait_for(_check("ATE->APP", ate, app, payload), 10.0)

async def app_to_ate(app, ate, size):
    if not size:
        return
    payload = bytes((x & 0xff) for x in range(size))
    await asyncio.wait_for(_check("APP->ATE", app, ate, payload), 10.0)

async def ate_to_app_all(app, ate):
    for size in range(1, 513):
        await ate_to_app(app, ate, swib(size, 9))

async def app_to_ate_all(app, ate):
    for size in range(1, 513):
        await app_to_ate(app, ate, swib(size, 9))
    
async def run(host, ate_port, app_port):
    hw = make_hw_root()
    try:
        app = await _open_app(hw, host, app_port)
        ate = await _open_ate(hw, host, ate_port)

        await app_to_ate(app, ate, 512)
        await asyncio.gather(ate_to_app_all(app, ate), app_to_ate_all(app, ate))
        
        print("loopback OK")
    finally:
        await lifecycle.shutdown()


async def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--ate-port", type=int, default=4242)
    ap.add_argument("--app-port", type=int, default=4243)
    args = ap.parse_args()
    await run(args.host, args.ate_port, args.app_port)


if __name__ == "__main__":
    asyncio.run_until_complete(main())
