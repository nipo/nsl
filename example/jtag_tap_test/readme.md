# Hooking custom logic to some JTAG TAP registers

This design shows how to hook a custom TAP register to custom logic.
It instantiates a `nsl_hwdep.jtag.jtag_user_tap` component that
abstract vendor-specific workings.  It requires declaration of
connection to the four JTAG signals, but it may not be necessary,
depending on backends.  For instance, in Xilinx chips, JTAG primitives
do not require user to wire the TAP signals.
