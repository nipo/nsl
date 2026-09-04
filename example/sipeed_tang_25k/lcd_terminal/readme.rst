===================
 Pmod LCD 0.96 text
===================

Displays a static 26x10 text screen on an iCESugar-style 0.96" 160x80
IPS LCD Pmod (ST7735S) plugged on J4, using the DVI terminal text
buffer and the 6x8 font.  Rows exercise the palette (red, green, blue
lines), the column ruler and corner markers make orientation and
mirroring obvious.  Done LED toggles every 32 frames as a refresh
heartbeat.

If the image is offset, mirrored or has wrong colors, adjust the
madctl_c, column_offset_c, row_offset_c and invert_c generics of
pmod_lcd_096_driver.
