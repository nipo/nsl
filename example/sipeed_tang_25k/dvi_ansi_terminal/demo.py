#!/usr/bin/env python3.13
"""Drive the dvi_ansi_terminal example over a serial port.

Sends ANSI escape sequences exercising the nsl_terminal.ansi engine:
colors, attributes, cursor motion, erase, scrolling, insert/delete
editing, and the device-status/attribute replies.
"""

import argparse
import time

import serial


class AnsiPort:
    """Serial port carrying ANSI sequences to the terminal."""

    ESC = "\x1b"
    CSI = ESC + "["

    def __init__(self, port, baudrate=115200, char_delay=0.0, step=0.2):
        self.char_delay = char_delay
        self.step = step
        self.serial = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            rtscts=False,
            dsrdtr=False,
            xonxoff=False,
            timeout=0.4,
            write_timeout=5.0,
        )
        # Let the adapter settle after the open toggles control lines
        time.sleep(0.2)

    def close(self):
        self.serial.flush()
        # Leave time for the kernel buffer to drain at line rate
        time.sleep(0.1)
        self.serial.close()

    def send(self, text):
        data = text.encode("latin-1")
        if self.char_delay > 0.0:
            for i in range(len(data)):
                self.serial.write(data[i:i+1])
                self.serial.flush()
                time.sleep(self.char_delay)
        else:
            self.serial.write(data)
            self.serial.flush()

    def pause(self, factor=1.0):
        if self.step > 0.0:
            time.sleep(self.step * factor)

    def ask(self, query, wait=0.3):
        self.serial.reset_input_buffer()
        self.send(query)
        time.sleep(wait)
        return self.serial.read(64)

    @classmethod
    def sgr(cls, *codes):
        return cls.CSI + ";".join(str(c) for c in codes) + "m"

    @classmethod
    def cup(cls, row, column):
        return cls.CSI + f"{row};{column}H"

    @staticmethod
    def readable(data):
        # Render control bytes so a reply can be printed inline
        out = []
        for b in data:
            if b == 0x1b:
                out.append("<ESC>")
            elif 32 <= b < 127:
                out.append(chr(b))
            else:
                out.append(f"<{b:02x}>")
        return "".join(out)


class Demo:
    """Scenes exercising the terminal engine."""

    def __init__(self, port):
        self.port = port

    def clear(self):
        self.port.send(AnsiPort.CSI + "2J" + AnsiPort.cup(1, 1))

    def banner(self):
        p = self.port
        p.send(AnsiPort.sgr(1, 32) + " NSL ANSI TERMINAL " + AnsiPort.sgr(0)
               + " - 85x48 @ XGA, fed over UART at 115200\r\n\r\n")

    def colors(self):
        p = self.port
        p.send("Standard: ")
        for i in range(8):
            p.send(AnsiPort.sgr(40 + i) + "    " + AnsiPort.sgr(0))
        p.send("\r\nBright:   ")
        for i in range(8):
            p.send(AnsiPort.sgr(100 + i) + "    " + AnsiPort.sgr(0))
        p.send("\r\n\r\n")

    def attributes(self):
        p = self.port
        for i in range(1, 7):
            p.send("  " + AnsiPort.sgr(30 + i) + "normal" + AnsiPort.sgr(0)
                   + "  " + AnsiPort.sgr(1, 30 + i) + "bold" + AnsiPort.sgr(0)
                   + "  " + AnsiPort.sgr(4, 30 + i) + "underline" + AnsiPort.sgr(0)
                   + "  " + AnsiPort.sgr(7, 30 + i) + "reverse" + AnsiPort.sgr(0)
                   + "\r\n")
        p.send("\r\n")

    def cursor(self):
        p = self.port
        p.send("Cursor: start" + AnsiPort.CSI + "s"
               + " ...far away..." + AnsiPort.CSI + "u"
               + AnsiPort.CSI + "20C"
               + AnsiPort.sgr(93) + "jumped here via save/restore"
               + AnsiPort.sgr(0) + "\r\n")
        p.send("Erase:  0123456789" + AnsiPort.CSI + "8D" + AnsiPort.CSI + "K"
               + AnsiPort.sgr(96) + "<- erased from 2" + AnsiPort.sgr(0)
               + "\r\n\r\n")

    def scroll(self, count=60):
        p = self.port
        p.send(f"Scroll test, {count} lines:\r\n")
        for i in range(1, count + 1):
            p.send(f"line {i:02d} of {count} - the screen should scroll smoothly\r\n")
        p.send(AnsiPort.sgr(95)
               + "Done. Readable at the bottom means scrolling works."
               + AnsiPort.sgr(0) + "\r\n")

    def edit(self):
        """Insert/delete of characters and lines, paced to be watched."""
        p = self.port
        self.clear()
        p.send(AnsiPort.sgr(1, 32) + " editing " + AnsiPort.sgr(0)
               + " - insert/delete characters and lines\r\n\r\n")

        p.send(AnsiPort.cup(4, 1) + "DCH:  "
               + AnsiPort.sgr(1, 33) + "The XXX quick XXX brown XXX fox"
               + AnsiPort.sgr(0))
        for _ in range(3):
            p.pause()
            p.send(AnsiPort.cup(4, 11) + AnsiPort.CSI + "4P")

        p.send(AnsiPort.cup(6, 1) + "ICH:  "
               + AnsiPort.sgr(1, 36) + "roses are" + AnsiPort.sgr(0))
        p.pause()
        p.send(AnsiPort.cup(6, 16) + AnsiPort.CSI + "7@")
        p.pause()
        p.send(AnsiPort.cup(6, 16) + AnsiPort.sgr(1, 35) + " red;-)"
               + AnsiPort.sgr(0))

        p.send(AnsiPort.cup(9, 1) + "IL/DL:\r\n")
        for i in range(1, 7):
            p.send(f"  original line {i}\r\n")
        p.pause()
        p.send(AnsiPort.cup(11, 1) + AnsiPort.CSI + "2L")
        p.send(AnsiPort.cup(11, 1) + AnsiPort.sgr(1, 32)
               + "  >> two lines inserted here <<" + AnsiPort.sgr(0))
        p.pause()
        p.send(AnsiPort.cup(14, 1) + AnsiPort.CSI + "1M")

        p.send(AnsiPort.cup(20, 1) + AnsiPort.sgr(1, 37) + "prompt$"
               + AnsiPort.sgr(0) + " type here _" + AnsiPort.CSI + "D")

    def boxes(self):
        """Nested filled rectangles via positioning and colored spaces."""
        p = self.port
        self.clear()
        specs = [(3, 4, 60, 20, 44), (6, 12, 44, 14, 46),
                 (9, 20, 28, 8, 45), (11, 28, 12, 4, 47)]
        for top, left, width, height, color in specs:
            for row in range(height):
                p.send(AnsiPort.cup(top + row, left)
                       + AnsiPort.sgr(color) + " " * width + AnsiPort.sgr(0))
        p.send(AnsiPort.cup(12, 30) + AnsiPort.sgr(1, 30, 47) + " NESTED "
               + AnsiPort.sgr(0))
        p.send(AnsiPort.cup(26, 4) + "Filled rectangles drawn cell by cell.\r\n")

    def spectrum(self):
        """One labelled bar per palette entry."""
        p = self.port
        self.clear()
        p.send(AnsiPort.sgr(1) + "16-color palette\r\n\r\n" + AnsiPort.sgr(0))
        for i in range(16):
            code = (30 + i) if i < 8 else (90 + i - 8)
            bg = (40 + i) if i < 8 else (100 + i - 8)
            fg = 0 if i in (7, 15) else 15
            p.send(f"  {i:2d} " + AnsiPort.sgr(code) + "text sample "
                   + AnsiPort.sgr(0) + AnsiPort.sgr(fg, bg)
                   + f"  bg {i:2d}  " + AnsiPort.sgr(0) + "\r\n")

    def wrap(self):
        """Auto-wrap at the right margin, TAB stops and backspace."""
        p = self.port
        self.clear()
        p.send(AnsiPort.sgr(1) + "wrap / tab / backspace\r\n\r\n" + AnsiPort.sgr(0))
        p.send("Auto-wrap: " + AnsiPort.sgr(93)
               + "".join(chr(65 + (i % 26)) for i in range(180))
               + AnsiPort.sgr(0) + "\r\n\r\n")
        p.send("Tab stops:\r\n")
        p.send("1" + "\t2" + "\t3" + "\t4" + "\t5" + "\t6" + "\r\n")
        p.send("col" + "\tcol" + "\tcol" + "\tcol" + "\r\n\r\n")
        p.send("Backspace: abcXYZ")
        p.send("\b\b\b" + AnsiPort.sgr(91) + "123" + AnsiPort.sgr(0)
               + " (XYZ overwritten)\r\n")

    def region(self):
        """Fixed header/footer with a scroll region in the middle."""
        p = self.port
        self.clear()
        p.send(AnsiPort.sgr(1, 30, 47) + " NSL ANSI TERMINAL - scroll region demo    "
               + AnsiPort.sgr(0) + "\r\n")
        p.send(AnsiPort.cup(48, 1) + AnsiPort.sgr(1, 30, 46)
               + " footer stays put while rows 3..46 scroll        "
               + AnsiPort.sgr(0))
        # Scroll region rows 3..46, leaving row 1 header and row 48 footer
        p.send(AnsiPort.CSI + "3;46r")
        p.send(AnsiPort.cup(46, 1))
        for i in range(1, 80):
            color = 32 + (i % 6)
            p.send(AnsiPort.sgr(color) + f"scrolling line {i:03d} - only the middle band moves"
                   + AnsiPort.sgr(0) + "\r\n")
            p.pause(0.15)
        # Release the region so the prompt behaves normally
        p.send(AnsiPort.CSI + "r" + AnsiPort.cup(46, 1))

    def query(self):
        """Ask device status/attributes and show the replies."""
        p = self.port
        self.clear()
        p.send(AnsiPort.sgr(1) + "device queries\r\n\r\n" + AnsiPort.sgr(0))

        da = p.ask(AnsiPort.CSI + "c")
        dsr = p.ask(AnsiPort.CSI + "5n")
        p.send(AnsiPort.cup(10, 20))
        cpr = p.ask(AnsiPort.CSI + "6n")

        rows = [
            ("DA  (CSI c)", da, "<ESC>[?6c"),
            ("DSR (CSI 5n)", dsr, "<ESC>[0n"),
            ("CPR (CSI 6n) at row 10 col 20", cpr, "<ESC>[010;020R"),
        ]
        p.send(AnsiPort.cup(12, 1))
        for label, data, expected in rows:
            got = AnsiPort.readable(data)
            colored = 32 if got == expected else 31
            line = f"  {label:34s} {got}"
            p.send(AnsiPort.sgr(colored) + line + AnsiPort.sgr(0) + "\r\n")
            print(f"{label}: {got!r} (expected {expected!r})")

    def full(self):
        self.clear()
        self.banner()
        self.colors()
        self.attributes()
        self.cursor()

    SCENES = ["full", "clear", "banner", "colors", "attributes", "cursor",
              "scroll", "edit", "boxes", "spectrum", "wrap", "region", "query"]

    def run(self, scene):
        getattr(self, scene)()


class Main:
    @staticmethod
    def run():
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("port", nargs="?",
                            default="/dev/cu.usbserial-20250303171",
                            help="serial port device")
        parser.add_argument("--baudrate", type=int, default=115200)
        parser.add_argument("--char-delay", type=float, default=0.0,
                            help="delay between characters, in seconds")
        parser.add_argument("--step", type=float, default=0.2,
                            help="pause between steps of paced scenes, in seconds")
        parser.add_argument("--scene", choices=Demo.SCENES, default=None,
                            action="append", dest="scenes",
                            help="scene to play, may be repeated (default: full)")
        parser.add_argument("--text", help="send this text instead of scenes, "
                            "\\e is replaced by ESC")
        args = parser.parse_args()

        port = AnsiPort(args.port, args.baudrate, args.char_delay, args.step)
        try:
            if args.text is not None:
                port.send(args.text.replace("\\e", AnsiPort.ESC) + "\r\n")
            else:
                demo = Demo(port)
                for scene in args.scenes or ["full"]:
                    demo.run(scene)
        finally:
            port.close()


if __name__ == "__main__":
    Main.run()
