import cocotb
import asyncio
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from cocotb.bus import Bus

@cocotb.coroutine
async def clock_dut(clock, half_period_ns, clock_done):
    while not clock_done.is_set():
        clock <= 0
        await Timer(half_period_ns, units='ns')
        clock <= 1
        await Timer(half_period_ns, units='ns')
    clock._log.debug("Clock terminated")

async def reset_dut(reset_n, duration_ns):
    reset_n <= 0
    await Timer(duration_ns, units='ns')
    reset_n <= 1
    reset_n._log.debug("Reset released")

class FramedWriter:
    def __init__(self, clock, o, i):
        self.clock = clock
        self.i = i
        self.o = o
        self.clear()

    def clear(self):
        self.o.valid <= 0
        self.o.data <= 0

    async def word_send(self, d, last):
        await FallingEdge(self.clock)
        self.o.last <= int(last)
        self.o.data <= d
        self.o.valid <= 1
        await RisingEdge(self.clock)
        while not self.i.ready.value:
            await RisingEdge(self.clock)
        self.o.data._log.info("Writing data")
        self.clear()
        
    async def send(self, data):
        for i, d in enumerate(data):
            await self.word_send(d, i == len(data) - 1)
        self.clear()

class FramedReader:
    def __init__(self, clock, o, i):
        self.clock = clock
        self.i = i
        self.o = o
        self.clear()

    def clear(self):
        self.o.ready <= 0

    async def word_get(self):
        await FallingEdge(self.clock)
        self.o.ready <= 1
        await RisingEdge(self.clock)
        while not self.i.valid.value:
            await RisingEdge(self.clock)
        self.i.data._log.info("Reading data")
        self.clear()
        data = self.i.data.value
        last = self.i.last.value
        return data, last
        
    async def recv(self):
        ret = []
        last = False
        while not last:
            data, last = await self.word_get()
            ret.append(data)
        return bytes(ret)

class Routed:
    def __init__(self, cmd, rsp, local_id):
        self.cmd = cmd
        self.rsp = rsp
        self.local_id = local_id
        self.tag = 0

    async def _send(self, dstid, tag, data):
        header = [(self.local_id << 4) | dstid, tag]
        await self.cmd.send(bytes(header) + bytes(data))

    async def _recv(self):
        frame = await self.rsp.recv()
        srcid = frame[0] >> 4
        dstid = frame[0] & 0xf
        tag = frame[1]
        data = frame[2:]
        assert dstid == self.local_id
        return srcid, tag, data

    async def transact(self, dstid, cmd):
        tag = self.tag
        self.tag += 1

        sender = cocotb.fork(self._send(dstid, tag, cmd))
        receiver = cocotb.fork(self._recv())
        
        await cocotb.triggers.Combine(sender, receiver)
        responder, tag, rsp = receiver.retval

        assert responder == dstid
        assert tag == tag
        return rsp

class Flushable:
    def __init__(self, routed, target_id):
        self.pipe = routed
        self.target_id = target_id

    async def transact(self, *cmd):
        cb = b''.join(x.cmd for x in cmd)
        rl = sum(x.rsp_len for x in cmd)
        rsp = await self.pipe.transact(self.target_id, cb)
        assert len(rsp) == rl

        point = 0
        for c in cmd:
            c.gather(rsp[point : point + c.rsp_len])
            point += c.rsp_len
    
class Command:
    def __init__(self, cmd, rsp_len):
        self.cmd = cmd
        self.rsp_len = rsp_len

    def gather(self, data):
        self.rsp = data

class Divisor(Command):
    def __init__(self, v):
        super().__init__(bytes([v & 0x1f]), 1)

class Start(Command):
    def __init__(self):
        super().__init__(bytes([0x20]), 1)

class Stop(Command):
    def __init__(self):
        super().__init__(bytes([0x21]), 1)

class Write(Command):
    def __init__(self, data):
        super().__init__(bytes([0x40 | (len(data) - 1)]) + data, len(data))

class Read(Command):
    def __init__(self, size, ack = True):
        super().__init__(bytes([0x80 | (int(bool(ack)) << 6) | (size - 1)]), size)
    
class I2cMaster(Flushable):
    pass

class I2cMemory:
    def __init__(self, master, saddr, addr_bytes):
        self.master = master
        self.saddr = saddr
        self.addr_bytes = addr_bytes

    async def write(self, addr, data):
        txn = Write(bytes([self.saddr << 1]) + addr.to_bytes(self.addr_bytes, "big") + data)
        await self.master.transact(
            Divisor(0x1f),
            Start(),
            txn,
            Stop(),
        )

        sel_ack = txn.rsp[0] & 1
        addr_ack = all(x & 1 for x in txn.rsp[1 : 1 + self.addr_bytes])
        data_ack = all(x & 1 for x in txn.rsp[1 + self.addr_bytes : -1])

        if not sel_ack:
            raise RuntimeError("Sel fail")

        if not addr_ack or not data_ack:
            raise RuntimeError("Data nack")

    async def read(self, addr, size):
        w = Write(bytes([self.saddr << 1]) + addr.to_bytes(self.addr_bytes, "big"))
        s = Write(bytes([(self.saddr << 1) | 1]))
        r = Read(size, False)

        await self.master.transact(
            Divisor(0x1f),
            Start(),
            w,
            Start(),
            s, r,
            Stop(),
        )

        sel_ack = w.rsp[0] & 1
        sel2_ack = s.rsp[0] & 1
        data = r.rsp

        if not sel_ack:
            raise RuntimeError("Sel W fail")

        if not sel2_ack:
            raise RuntimeError("Sel R fail")

        return data

@cocotb.test()
async def some_test(dut):
    clock_done = asyncio.Event()
    clock_done.clear()
    clock_thread = cocotb.fork(clock_dut(dut.clock_i,
                                         half_period_ns = 5,
                                         clock_done = clock_done))

    await reset_dut(dut.reset_n_i, duration_ns = 100)

    cmd_pipe = FramedWriter(dut.clock_i,
                            Bus(dut, "cmd_i", ["valid", "data", "last"]),
                            Bus(dut, "cmd_o", ["ready"]))
    rsp_pipe = FramedReader(dut.clock_i,
                            Bus(dut, "rsp_i", ["ready"]),
                            Bus(dut, "rsp_o", ["valid", "data", "last"]))
    noc = Routed(cmd_pipe, rsp_pipe, 0xf)
    i2c = I2cMaster(noc, 0x0)
    mem = I2cMemory(i2c, 0x26, 2)

    await mem.write(0, b'deadbeef')
    assert await mem.read(0, 8) == b'deadbeef'

    
    clock_done.set()
    await clock_thread

