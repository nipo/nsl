=======================
 Random Pkt Checker
=======================

This test is a random packet player based on generated commands and PRBS random data generation, 
intended for general interface testing. All the buses are AXI4-Stream. 
A module inserts random errors into the stream, and the packet validator must detect them and resynchronize. 
If it fails, a counter is incremented and its value is displayed on a seven-segment display.