from crobe.adapter import model
from crobe.protocol import jtag, base
from crobe import bitstring
from crobe.util.pretty import metric, sci_parse
from crobe.util import endian
from crobe.db import NoMatch
import usb.core
import usb.util
import binascii
import time
import os
import math
import struct
import threading
from crobe.component.nsl.transactor.cs import ControlStatus
from crobe.component.nsl.bnoc import routed
import enum

__all__ = []

class Registers(ControlStatus):
    GPIO0 = 0
    GPIO1 = 1

    def reg_update(self, id, mask, new_value):
        if not mask:
            return
        old = self.reg_read(id)
        new = (old & ~mask) | (new_value & mask)
        self.logger.debug("RMW %d: 0x%08x + (0x%08x &  0x%08x) ->  0x%08x",
                          id, old, mask, new_value, new)
        self.reg_write(id, new)

    def gpio_set(self, mask, value):
        self.reg_update(self.GPIO1, mask >> 32, value >> 32)
        self.reg_update(self.GPIO0, mask & 0xffffffff, value & 0xffffffff)

class JtagInterface(jtag.Interface):
    def __init__(self, framed_jtag, base_freq, regs):
        from crobe.component.nsl.transactor.jtag import JtagTransactor
        self.jtag = JtagTransactor(framed_jtag, base_freq)
        super().__init__(self.jtag, "jtag")

    def execute(self, op_list):
        self.jtag.execute(op_list)

    def freq_update(self, freq):
        freq = min(freq or 5e6, 5e6)
        return self.jtag.freq_update(freq)
    
@model.UsbEnumerator.db.register(model.UsbInfo(idVendor = 0xdead, idProduct = 0xdf55, bcdDevice = 0x0100))
class Adapter(model.Adapter):
    """
    NSL NeoRV32 integration demo
    """
    supported_interfaces = ["jtag"]

    @classmethod
    def from_device(cls, d):
        serial = usb.util.get_string(d, d.iSerialNumber)
        return cls(d, "neo-%s" % (serial,))

    def __init__(self, device, name):
        model.Adapter.__init__(self, name)
        self.handle = device
        self.io = None

    def _open(self):
        if self.io:
            return

        cfg = self.handle.get_active_configuration()
        if cfg.bConfigurationValue == 0:
            self.handle.set_configuration(1)
            cfg = self.handle.get_active_configuration()
        for intf in cfg:
            self.logger.debug("Has interface %d, %02x:%02x:%02x",
                  intf.index,
                  intf.bInterfaceClass,
                  intf.bInterfaceSubClass,
                  intf.bInterfaceProtocol)
            if intf.bInterfaceClass == 0xff and \
               intf.bInterfaceSubClass == 0xff and \
               intf.bInterfaceProtocol == 0xff:
                self.intf = intf
                break
        usb.util.claim_interface(self.handle, self.intf)

        self.ep_in = usb.util.find_descriptor(
            self.intf,
            custom_match = lambda e:
            usb.util.endpoint_direction(e.bEndpointAddress) ==
            usb.util.ENDPOINT_IN)
        self.ep_out = usb.util.find_descriptor(
            self.intf,
            custom_match = lambda e:
            usb.util.endpoint_direction(e.bEndpointAddress) ==
            usb.util.ENDPOINT_OUT)

        self.logger.debug("Using interface %d, EP_IN: %02x, EP_OUT: %02x",
                          self.intf.index,
                          self.ep_in.bEndpointAddress,
                          self.ep_out.bEndpointAddress)

        self.io = model.BulkDatagramInterface(self, self.handle, "io", self.ep_out, self.ep_in)
        self.child_add(self.io)
        
        r = routed.Router(self.io)
        self.child_add(r)

        self.regs = Registers(r.route(0xf, 0x0).framed_endpoint())
        self.child_add(self.regs)
        self.base_freq = 60e6

        self.jtag = JtagInterface(r.route(0xf, 0x1).framed_endpoint(), self.base_freq, self.regs)
        self.child_add(self.jtag)

    def open(self, interface_name):
        self._open()

        if interface_name.lower() == "jtag":
            return self.jtag
