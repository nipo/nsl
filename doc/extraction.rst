=====================================
Partial design reuse from the library
=====================================

Maybe you like some function of the library but you don't want to be
dependent on it in the long term. You may extract a function from the
library in two different ways.

Extracting a packaged IP
========================

This is typically done for Vivado or other IP-Xact-compatible
tools. NSL supports using Vivado as an IP-Xact encapsulation
tool. Result is an IP package suitable for usage in Vivado's block
design tool (at least). Compatilility with third-party tools may vary.

There are examples of such tool usage in `packaging/src`. More IPs can
be declared there if needed.  Each IP is then self-contained, pulling
all the dependencies internally.

Resulting IP is dependant on the hardware-specific cells, if any
(mostly IO blocks).

Extracting a dependency set
===========================

You may as well declare a set of dependencies to some module, and let
the tools extract all the dependencies.  Extraction result is a bunch
of sources files that need to be compiled in a certain order and for
some given set of library names.

See in `example/extract`.