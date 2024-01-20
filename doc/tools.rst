=====================
 Synthesis/PNR Tools
=====================

GHDL
----

GHDL can handle simulation of VHDL sources. Running simulation will
generate a full trace of all signals::

  top = work.tb
  work-srcdir = $(SRC_DIR)/src
  tool = ghdl
  
  include $(NSL)/build/build.mk

ISIM
----

ISIM is Xilinx' simulator from the ISE era. It transparently handles
Xilinx-specific libraries (unisim, unimacros). It also comes with a
fair-enough GUI for interactive tracing.

  top = work.tb
  work-srcdir = $(SRC_DIR)/src
  tool = isim
  
  include $(NSL)/build/build.mk

ISE
---

Xilinx tool for pre-7-Series targets. Mostly tested with Spartan-6 as
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
  
  include $(NSL)/../build/build.mk

It drives Xilinx XST, PAR, BITGEN and other tools down to the
(compressed) bitstream.

Planahead project
-----------------

Goal of this backend is to generate a working planahead project file
that can be opened in PlanAhead afterwards. This makes little interest
and is mostly unsupported.

Vivado project
--------------

This backend creates a Vivado project for opening in Vivado. It relies
on user interaction for the rest of the compilation. This is mostly
unsupported.

Vivado
------

This backend internally creates a Vivado project on the fly and drives
the synthesis/PNR process down to a bitstream file.  This is the
preferred usage for 7-series.

Vivado IP
---------

This backend uses Vivado for packaging design topcell as an IP that can in
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
  ip-company-url = http://www.example.com

  # Target family filter
  target_families = zynq

  # Target for synthesis, for checking purposes
  target_part = xc7z020
  target_package = clg400
  target_speed = -1

  include $(NSL)/build/build.mk

Gowin
-----

Gowin backend. Mostly the same requirement and usage than ise
backend::

  target = blink
  top = work.top
  work-srcdir = $(SRC_DIR)/src
  target_part_name = GW1N-9C
  target_part = GW1N-UV9UG256C6/I5
  hwdep = gowin
  tool = gowin
  gowin-use-as-gpio = sspi mspi
  
  all: $(target).fs
  
  include $(NSL)/../build/build.mk

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
  
  include $(NSL)/../build/build.mk

Diamond
-------

Lattice Mach/ECP backend. Mostly the same requirement and usage than icecube2
backend::
  
  all: $(target).bin
  
  include $(NSL)/../build/build.mk
