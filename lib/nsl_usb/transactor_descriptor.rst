=========================================
 NSL-Specific transactor tree descriptor
=========================================

An NSL-built USB device exposing a NSL bnoc structure and transactors
(SWD, JTAG, SPI, I2C, ...) can expose a NSL-specific vendor descriptor
in the configuration along the interface that serves the bnoc root.

Descriptor Structure
====================

When a pair of bulk endpoints are used to access a bnoc root, it may
either be a routed or a framed noc. If routed, first reached block
will be a router. The other way around, if network is directly a
framed noc, target will be a framed target. So rather than defining
noc type for each edge, we'll only define targets.

Most of the time, target topology is a tree. If topology is not a
tree, it must be a direct acyclic graph, and joins should only happen
in master/slave devices that do not pass transactions through, but act
as a standalong master.  This kind of topology can be handled, as
messages never go through A to B:

::

                   /----> Slave/master --\
   Root  --> Router           (A)         Router ---> Slave (B)
    (R)            \---------------------/


As such, when defining topology as seen from R, presence of A as a
master on the NOC is unimportant. Overall, topology as seen from R is
a tree.

Each node in tree will be described in turn. A node will be
responsible for embedding definitions of all nodes in its subtree, if
any. This allows to parse tree from a host where some node handling is
unknown. They will remain black boxes, but rest of the tree will be
usable.

Descriptor header
=================

Descriptor header will be formatted a a standard USB descriptor to be
inserted in the configuration descriptor, after the matching interface
descriptor.

* bLength: Variable, total descriptor blob size
* bDescriptorType: 0xff, manufacturer specific
* dwNslIdentifier: 'N', 'S', 'L', 0x01. Identifies a NSL transactor
  tree descriptor
* ... Root node descriptor follows

Node descriptor
===============

All nodes has the following descriptor format:

* uint8 bLength
* uint8 bNodeDescriptorType
* uint8 bNodeVersion
* ... other node specific data

Router descriptor
-----------------

NSL bnoc routed router, as of current code base, is defined as:

* uint8 bLength: variable, concatination of all descriptors of
  all subtree.
* uint8 bNodeDescriptorType: 0x00, constant for NSL Bnoc Routed Router.
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint8 bRoutingInfo: Response routing information index (4 MSBs),
  number of downstream ports "N" (4 LSBs, offset by 1 (value of 0
  means 1 port)).
* N node descriptors follow.

Routed Endpoint
---------------

NSL bnoc routed endpoint decapsulates routing information and targets
one framed endpoint. Its descriptor embeds downstream framed target
definition.

* uint8 bLength: variable, present descriptor + downstream.
* uint8 bNodeDescriptorType: 0x01, constant for NSL Bnoc Routed Endpoint.
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* 1 node descriptor follows.

SWD Transactor
--------------

SWD transactor has the following descriptor:

* uint8 bLength: 5
* uint8 bNodeDescriptorType: 0x10
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint16 wBasePeriod: Reference clock cycle period, in picoseconds.

SPI Transactor
--------------

SPI transactor has the following descriptor:

* uint8 bLength: 6
* uint8 bNodeDescriptorType: 0x11
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint8 SlaveCount: Number of slave selects, offset by 1
* uint16 wBasePeriod: Reference clock cycle period, in picoseconds.

I2C Transactor
--------------

I2C transactor has the following descriptor:

* uint8 bLength: 5
* uint8 bNodeDescriptorType: 0x12
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint16 wBasePeriod: Reference clock cycle period, in picoseconds.

WS2812 Transactor
-----------------

WS2812 transactor has the following descriptor:

* uint8 bLength: 4
* uint8 bNodeDescriptorType: 0x13
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint8 LedCount: number of LEDs in strip. 0 means undeterminate.

SMI Transactor
--------------

SMI transactor has the following descriptor:

* uint8 bLength: 3
* uint8 bNodeDescriptorType: 0x14
* uint8 bNodeVersion: 0x00, constant at time of this writing.

JTAG Transactor
---------------

JTAG transactor has the following descriptor:

* uint8 bLength: 5
* uint8 bNodeDescriptorType: 0x15
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint16 wBasePeriod: Reference clock cycle period, in picoseconds.

Ti Easyscale Transactor
-----------------------

Ti-Specific "Easyscale" master transactor has the following
descriptor:

* uint8 bLength: 3
* uint8 bNodeDescriptorType: 0x16
* uint8 bNodeVersion: 0x00, constant at time of this writing.

Ti Chipcon Transactor
---------------------

Ti-Specific "Chipcon" debug interface transactor has the following
descriptor:

* uint8 bLength: 5
* uint8 bNodeDescriptorType: 0x17
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint16 wBasePeriod: Reference clock cycle period, in picoseconds.

Framed Control/Status
---------------------

Control/status accessor has the following descriptor:

* uint8 bLength: Variable
* uint8 bNodeDescriptorType: 0x18
* uint8 bNodeVersion: 0x00, constant at time of this writing.
* uint8 bControlCount (can be 0)
* uint8 bStatusCount (can be 0)
* Undefined control/status application-specific descriptor blob. Can
  contain register-specific information.
