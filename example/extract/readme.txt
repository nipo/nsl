This is an example of partial library extraction.

Makefile in this directory defines where to find top module and
hardware-dependant target, if any. It may be left blank, in such
cases, no hardware-specific blocks will be defined.

Top module is called "srclib.top", "srclib" source directory is
`src/`.

In `src/Makefile`, we do not define any source file, but only
dependencies to NSL modules. They act as the entry point for
dependency collection.

Resolved library order gets extracted as a bunch of portable
VHDL/Verilog/... files, named in compilation order.