==========================
Nice Synthesizable Library
==========================

NSL is a nice library of VHDL models, along with a build system for
various backend tools, either simulation or synthesis.

VHDL libraries
==============

NSL was first created as a framework for making debug probes and
tools.  It has a strong bias towards serial protocol implementations,
but also contains the usual foundation features of a FPGA library.

Clocking
--------

`lib/nsl_logcking/` contains some comprehensive clock-related
operations like:

* Sampling asynchronous data,
* Crossing clock domains,
* Intra-domain operations.

All these blocks come with generic constraints that apply the intended
behavior.

Math and bit manipulation
-------------------------

`lib/nsl_math` contains some basic arithmetic primitives, but also
gray encoder/decoder, and some basic logic routines.

I/O
---

IO library is mostly constituted of packages defining explicit record
datatypes of various IO modes (opendrain, directed, tri-stated,
differential).

Hardware-dependant
------------------

Even if most library tries to use inference and refrains using
vendor-specific libraries, some parts are still vendor-specific.
Hardware-dependant library contains:

* Access to internal built-in oscillators of FPGAs,
* Access to internal built-in reset of FPGAs,
* Access to User-defined DRs of FPGAs JTAG TAPs,
* IO cells (ddr),
* IO pads (differential IOs).

Protocol tooling library
------------------------

This library is the reason NSL was built, and then got the "nsl"
name. It contains:

* A NOC model built around 8-bit flits with a split command/response
  network,
* JTAG, SWD, I2C, SPI, ChipCon debug protocol, WS2812, UART master
  transactors,
* MII/RMII to Fifo bridges,
* FT245 Synchronous Fifo interface transactor.

Simulation helpers library
--------------------------

Simulation library contains either helpers for test-benches:

* feeding a fifo from a file,
* comparing fifo contents with a file,
* driving reset and clocks in a test-bench context.

Build System
============

Build system relies on GNU Make. It is pluggable in the sense there
may be out-of-tree libraries and projects that reuse NSL core and
build system. For instance, NSL can be used as a git submodule from a
wrapper project.

There are different types of Makefiles in the tree.

Library makefiles
-----------------

Library makefiles should only point to packages. A typical library
Makefile contains::

  packages += foo
  packages += bar

Then in library directory, along with the Makefile, there should be
`foo` and `bar` directories for matching packages. Each of them should
contain a Package Makefile.

Package makefiles
-----------------

Package makefiles should enumerate package-related HDL source files,
and dependencies of the package on other packages.  A typical `foo`
package Makefile contains::

  vhdl-sources += foo.pkg.vhd
  vhdl-sources += foo_module_1.vhd
  vhdl-sources += foo_module_2.vhd
  deps += other.baz

Here package `foo` is composed of 3 VHDL source files, one package and
two modules. Naming of files is conventional only and is not enforced
by tools.

Dependencies are in the form `library.package`, and may reference
packages in the same library or others. Dependency cycles are
unsupported and should be avoided.

Note about package names and dependencies::

  Packages, in terms of VHDL namespacing, do not technically have to
  match the package directory name and deps variables. The
  build-system does not parse the HDL files contents. The only
  requirement is that build-system dependencies target
  build-system-declared package names (i.e. `deps += a.b` should match a
  `package += b` in library `a`).

Project makefiles
-----------------

Project makefiles share a common structure, but then have a big
backend-specific part. See relevant chapter for build backends.

Common part takes care of enumerating:

* Libraries (in-tree libraries in `lib/` are automatically
  enumerated),
* Top module (root of design),
* Build backend specifics: target, constraints, etc.

Most of the time, project makefile declares the "work" library with a
path relative to the project makefile, and declares "top" module to be
some cell in the "work" library::

  target = my_project
  top = work.top
  work-srcdir = $(SRC_DIR)/src
  tool = ghdl

  include path/to/nsl/build/build.mk

Then in src/Makefile, we have a (non-hierarchic) library containing
only one (or multiple) module::

  vhdl-sources += top.vhd
  deps += mylib.bar

`top=` variable defines a `library.entity` name to use as top cell
(`library.package.entity` notation may also be used).

That's actually the `work` library source directory that pulls the
dependencies from the rest of the library with `deps +=` lines.

`target =` simply defines the project output base name.

Two special variables may select different HDL implementation files
from the build-system: `hwdep` selects the hardware-dependent vendor
library, `target_part` defines the target part, allowing to select for
hardware-specific cells.

`tool =` defines the backend, all other variable are tool-specific.

Tools
=====

GHDL
----

GHDL can handle simulation of VHDL sources. Running simulation will
generate a full trace of all signals::

  top = work.tb
  work-srcdir = $(SRC_DIR)/src
  tool = ghdl
  
  include ../../build/build.mk

NVC
---

NVC is mostly the same usage as GHDL::

  top = work.tb
  work-srcdir = $(SRC_DIR)/src
  tool = nvc
  
  include ../../build/build.mk

ISIM
----

ISIM is Xilinx' simulator. It transparently handles Xilinx-specific
libraries (unisim, unimacros). It also comes with a fair-enough GUI
for interactive tracing.

  top = work.tb
  work-srcdir = $(SRC_DIR)/src
  tool = isim
  
  include ../../build/build.mk

ISE
---

Xilinx tool for pre-series-7 targets. Mostly tested with Spartan-6 as
a target. Requires `target_part`, `target_package` and `target_speed`
variables.  UCF constraints can be added to `constraints` variable::

  target = blink
  top = work.top
  work-srcdir = $(SRC_DIR)/src
  target_part = xc6slx9
  target_package = tqg144
  target_speed = -2
  constraints += $(SRC_DIR)/led.ucf
  hwdep = xilinx
  tool = ise
  
  all: blink-compressed.bit
  
  include ../../../build/build.mk

It drives Xilinx XST, PAR, BITGEN and other tools down to the
(compressed) bitstream.

Planahead project
-----------------

Goal of this backend is to generate a working planahead project file
that can be opened in PlanAhead afterwards. This makes little interest
and is mostly unsupported.

Vivado
------

This backend creates a Vivado project on the fly and drives the
synthesis process down to a bitstream file.

Block-design source files and external IPs are unsupported for now.

Vivado IP
---------

This backend uses Vivado for packaging a topcell as an IP, that can in
turn be used in Vivado's board design. This is useful for building IPs
from NSL basic blocks, and integrating them in a Zynq design::

  top = work.activity_monitor

  # Usual input topcell description
  work-srcdir = $(SRC_DIR)/src
  hwdep = xilinx
  tool = vivado-ip

  # Generated IP properties, will appear in Vivado's IP listings
  ip-taxonomy = /Utilities
  ip-library = util
  ip-name = activity_monitor
  ip-display-name = Signal activity monitor
  ip-description = Toggles a signal when some activity happens on a wire
  ip-version = 1.0
  ip-revision = 1
  
  ip-vendor = nsl
  ip-display-vendor = NSL
  ip-company-url = http://www.ssji.net

  # Target family filter
  target_families = zynq

  # Target for synthesis, for checking purposes
  target_part = xc7z020
  target_package = clg400
  target_speed = -1

  include path/to/nsl/build/build.mk

Icecube2
--------

Lattice ICE40 backend. Mostly the same requirement and usage than ise
backend::

  target = blink
  top = work.top
  work-srcdir = $(SRC_DIR)/src
  target_part = iCE40HX1K
  target_package = TQ144
  target_speed =
  constraints += $(SRC_DIR)/led.pcf
  hwdep = lattice
  tool = icecube2
  
  all: $(target).bin
  
  include ../../../build/build.mk

Diamond
-------

Lattice Mach/ECP backend. Mostly the same requirement and usage than icecube2
backend::
  
  all: $(target).bin
  
  include ../../../build/build.mk
