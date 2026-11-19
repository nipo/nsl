
=================
USB communication
=================

Overview
========

As of writing this document, library contains an USB function IP set
with the following features:

* USB-2.0 Function role support (Device), also supports USB-1.1
  FS-only operation.

* Lots of types definitions and constants (see usb/usb.pkg.vhd).

* Clean interface separation with layering and strong interface
  typing:

  * Transfers (A Token, Data, Handshake triplet, see in
    sie/sie.pkg.vhd),

  * Packets (Low level data exchange on bus, see in sie/sie.pkg.vhd),

  * UTMI interface (see in utmi/utmi.pkg.vhd),

  * ULPI interface (see in ulpi/ulpi.pkg.vhd).

* Flexible interfacing, can work at the

  * UTMI level, natively;

  * ULPI level, through a pipelining adapter,

  * Direct FS bus wires, through HDL FS UTMI Phy.

* Flexible clocking:

  * any clock can be fed into the SIE (but most probably synchronous
    to Phy interface),

  * FS-only HDL UTMI Phy (ported design) can accept 48 or 60 MHz.

* Arbitrary endpoint arrangement:

  * Endpoints are separated from SIE, user may instantiate them as
    needed.

  * Generic support for halting endpoints from EP0.

  * Bulk In/Out and Interrupt In supported for now.

* Arbitrary descriptor support:

  * User gives the descriptor as a blob through generics,

  * There is a generic descriptor-generating set of functions (see in
    descriptor/descriptor.pkg.vhd),

  * Control EP 0 will accept to serve any descriptor without code
    modification.

* Testing:

  * USB-1.1 FS testing at the bus signal level (foreign ported code),

  * USB-2 HS testing at the UTMI level (including testing of
    bulk/control corner case behavior).

* Predefined function cores:

  * CDC-ACM function.

* CDC-NCM data path (see ncm/): NTB16 stream to/from ethernet frames
  (nsl_inet stream conventions, no FCS), AXI4-Stream at 1 or 2 bytes
  per beat, with bnoc (pipe / framed / committed) wrappers; helpers for
  the NCM functional descriptor (descriptor/), GET_NTB_PARAMETERS and
  notifications. Usable behind any bulk transport, e.g. the FX2 slave
  FIFOs, as the NTB framing needs no transfer boundaries.

Host side, the library contains a standalone low-/full-speed host
dedicated to HID devices (see hid_host/):

* Bit-banged low-speed (1.5Mb/s) signaling on D+/D- from a 12MHz
  clock, no CPU, no external Phy.  Full speed (12Mb/s, with
  start-of-frame generation) is optional and needs a 48MHz clock.

* Microcoded engine whose program is written as VHDL constants and
  assembled at elaboration (see ukp.pkg.vhd and hid_program.pkg.vhd);
  poll interval and report length are generics.

* Enumeration of the single attached device with identity capture
  (VID/PID, interface class/subclass/protocol) exposed to the design,
  interrupt IN endpoint polling with CRC16 checking, reports emitted
  as AXI4-Stream frames.

* Optional output reports to an interrupt OUT endpoint, taken as
  AXI4-Stream frames: one report buffered, sent with the right
  DATA0/DATA1 toggle and CRC16, retried on NAK or silence, dropped on
  STALL (``hid_program(..., output_enabled => true)``).

* Generic field extractor mapping report bytes/bits to parallel
  values, and boot-protocol keyboard and mouse wrappers with identity
  matching.

* Wire-level low-speed device BFM in nsl_usb.testing for closed-loop
  simulation, with interrupt IN and OUT endpoints.

* Not supported by design: hubs, HID report descriptor parsing.

The host is a reimplementation of ideas pioneered by two projects:
hi631's microcoded USB host in the Tang Nano 9K NES port
(https://github.com/hi631/tang-nano-9K/tree/master/NES) and
nand2mario's usb_hid_host
(https://github.com/nand2mario/usb_hid_host), which extended it with
device-type detection.  The microcode machine model, its timing
discipline and the enumeration sequence come from their work.

* TODO:

  * Add support for handling device (vendor), class/endpoint (Std,
    vendor) control requests.

  * Rework interface between SIE and interfaces/endpoints to fit in
    nsl_bnoc.committed (which would facilitate the previous point).
