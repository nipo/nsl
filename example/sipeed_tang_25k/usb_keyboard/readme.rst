======================
USB keyboard on a LCD
======================

A low-speed USB HID host (``nsl_usb.hid_host``) driving the USB-A
port of the Tang Primer 25K dock, with the 0.96" ST7735 LCD pmod on
J4 showing what the host sees:

* Top row: live line of decoded characters
  (``hid_host_keyboard_events`` + ``hid_host_keyboard_repeat`` +
  ``hid_host_keyboard_chars``); printable characters append, Enter
  clears the line, Backspace deletes, held keys auto-repeat.  Arrow
  and function keys emit their VT escape sequences, whose printable
  tail shows up as-is (e.g. ``[A`` for Up) since the line editor
  drops the escape byte.

* ``LINK``: ``SEARCHING`` while no device is enumerated, ``NOT A
  KBD`` when the attached device is not a boot-protocol keyboard,
  ``OK`` (green) when a keyboard is operational.

* ``DEV``: VID:PID of the enumerated device.

* ``MOD``: one letter per boot-report modifier bit
  (``CSAGcsag`` for left/right control, shift, alt, gui), ``.`` when
  released.

* ``KEYS``: the 6 scancode slots of the latest boot report, in hex.

The host engine bit-bangs low-speed USB on the D+/D- pins (L6/K6)
directly; the FPGA weak pull-downs stand in for the host-side 15k
terminations.  Only low-speed keyboards enumerate: a full-speed-only
keyboard stays on ``SEARCHING``.

The whole design runs at 12MHz out of a PLL, as required by the host
engine; the LCD SPI ends up at 6MHz.

Build and load::

  gbs project build
  programmer_cli --cable-index 4 --device GW5A-25A --operation_index 2 \
    -f usb_keyboard.fs --frequency 15MHz
