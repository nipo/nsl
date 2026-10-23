library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Digital Video Port, the parallel output of most CMOS image
-- sensors: a pixel clock, a byte-wide data bus, a frame sync and a
-- line valid (HREF).
package dvp is

  -- Receives a DVP bus in its own pixel clock domain and pairs bytes
  -- into 16-bit words, first byte of a line in the upper half.  This
  -- matches 16-bit sensor formats (RGB565, YUV422) where a pixel, or
  -- a pair of components, spans two bus cycles.
  --
  -- Bus is sampled on rising edge of pclk_i.  Sensors driving the
  -- bus on rising edge need their PCLK polarity inverted.
  --
  -- sof_o flags the first word after a frame sync, sol_o the first
  -- word of each line.  A line holding an odd byte count loses its
  -- last byte.  There is no backpressure: whatever takes words has
  -- to absorb them as they come.
  component dvp_receiver is
    generic(
      -- Level of vsync_i during frame sync.
      vsync_active_c: std_ulogic := '1';
      -- Level of href_i while line data is valid.
      href_active_c: std_ulogic := '1'
      );
    port(
      pclk_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      vsync_i: in std_ulogic;
      href_i: in std_ulogic;
      data_i: in std_ulogic_vector(7 downto 0);

      valid_o: out std_ulogic;
      sof_o: out std_ulogic;
      sol_o: out std_ulogic;
      data_o: out std_ulogic_vector(15 downto 0)
      );
  end component;

end package;
