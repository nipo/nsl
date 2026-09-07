======================
 Pmod OLEDrgb labels
======================

Displays a status screen on a Digilent Pmod OLEDrgb (SSD1331)
plugged on J4, using the DVI terminal label generator and the 6x8
font.  The screen layout is a constant, the text and the colors are
signals: uptime since configuration rendered as a date and time from
the Unix epoch, the count of frames sent to the panel, and a status
line that flips between "ok" in green and "--" in red every four
seconds.  Done LED toggles every 32 frames as a refresh heartbeat.

Program with::

  /opt/Gowin/current/Programmer/bin/programmer_cli --location 4657 \
    --device GW5A-25B --operation_index 2 --fs $PWD/oled_labels.fs
