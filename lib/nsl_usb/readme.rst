
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

* TODO:

  * Add support for handling device (vendor), class/endpoint (Std,
    vendor) control requests.

  * Rework interface between SIE and interfaces/endpoints to fit in
    nsl_bnoc.committed (which would facilitate the previous point).
