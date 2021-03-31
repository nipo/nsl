set_property BITSTREAM.CONFIG.USERID [format "0x%04x%04x" [expr {int(rand()*65536)}] [expr {int(rand()*65536)}]] [current_design]
