
AXI4-Stream Endpoint
====================

AXI4 Stream endpoint is a component mapping a pair of AXI4-Streams
interfaces (one each direction) to an AXI4-MM set of registers.

AXI4 Lite variant
-----------------

`axi4_stream_endpoint_lite` is a component where endpoint on
memory-mapped side is an AXI-Lite. It is sufficient for slow data
flows.

It only supports 32-bit data width configuration on MM side, and at
most a 24-bit wide stream side.

There are 7 registers defined:

* 0x00: Input data, read only. Read returns the following fields:

  * Bit 31: valid bit

  * Bit 30: last bit

  * Bit 23-0: Stream beat value (in 16-bit or 8-bit, data is aligned
    towards LSBs).

* 0x04: Ouptut data, write only.

  * Bit 31: valid bit

  * Bit 30: last bit

  * Bit 23-0: Stream beat value (in 16-bit or 8-bit, data is aligned
    towards LSBs).

* 0x08: Input status, read only:

  * Bit 31: whether there at least one beat waiting.

  * Bit 30: whether next waiting beat is last.

  * Bit 23-0: Count of waiting beats in RX Fifo

* 0x0c: Output status, read only:

  * Bit 31: whether there at room available in TX fifo

  * Bit 23-0: Count of free beats in TX Fifo

* 0x10: IRQ State, read only:

  * Bit 0: whether there at least one beat waiting in RX fifo

  * Bit 1: whether there at least one beat free in TX fifo

* 0x14: IRQ mask, enable high, same bit definition as register at 0x10

* 0x18: Configuration word, constant, read-only

  * 31-30: Stream-side data byte count (1 to 3)

  * 29-15: Output fifo total depth

  * 14-0: Input fifo total depth

Component is capable of generating an IRQ, it will be active (low) as
long as IRQ state AND IRQ mask give at least one active bit.