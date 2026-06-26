import asyncio
import ausb
import time

def blob_gen(x):
    return b''.join(x.to_bytes(4, "little") for x in range(x, x+1024))

async def writer_task(ep):
    for i in range(1024):
        blob = blob_gen(i)
        #print(">", end = "", flush = True)
        pending = []
        for off in range(0, len(blob), ep.mps):
            pending.append(ep.write(blob[off : off + ep.mps]))
        await asyncio.gather(*pending)
        #print("<", end = "", flush = True)

class BufferedReader:
    def __init__(self, ep):
        self.ep = ep
        self.q = asyncio.Queue()
        self.remainder = b""
        self.reader = asyncio.create_task(self.reader())

    async def reader(self):
        while True:
            await self.q.put(await self.ep.read(self.ep.mps))

    async def read(self, size):
        while True:
            if len(self.remainder) >= size:
                ret = self.remainder[:size]
                self.remainder = self.remainder[size:]
                return ret

            self.remainder += await self.q.get()
        
async def reader_task(ep):
    start = time.time()
    reader = BufferedReader(ep)
    transferred = 0
    for i in range(1024):
        blob = blob_gen(i)
        #print("+", end = "", flush = True)
        data = await reader.read(len(blob))
        if data != blob:
            for i in range(0, len(data), 16):
                print(f"OUT {i:4x}: {blob[i:i+16].hex()}")
                print(f"IN  {i:4x}: {data[i:i+16].hex()}")
            raise ValueError()
        #print("-", end = "", flush = True)
        transferred += len(data)
    end = time.time()

    print(f"{transferred} bytes in {end - start:0.2f}s, {transferred / (end - start):g}B/s, {transferred / (end - start) * 8 * 2:g}bps fd")

async def main(vid, pid):
    c = ausb.Context(loop)
    device = c.device_get(vendor_id = vid, product_id = pid)
    config, = device.configurations
    intr, data = config
    setting, = data
    ep_in, ep_out = setting

    handle = device.open()
    handle.configuration = config.number
    intf = handle.interface_claim(1)

    o = intf.open(ep_out)
    i = intf.open(ep_in)

    await o.write(b"flush")
    await i.read(i.mps)
    
    await asyncio.gather(
        writer_task(o),
        reader_task(i),
    )

if __name__ == "__main__":
    import sys
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main(int(sys.argv[1], 16), int(sys.argv[2], 16)))
