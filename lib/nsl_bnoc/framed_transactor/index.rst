===================
 Framed transactor
===================

Presentation
============

`Framed transactor once` module is a component issuing a bunch of
transactions on a framed network master port when asked for.  As
routed is a subtype of framed, it may also issue a bunch of routed
transasctions as well.  This is typically used to initialize a bunch
of components on reset of FPGA, without the need for a soft-core.
