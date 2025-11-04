library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.endian.all;

-- This package provides components for handling AXI4-Stream metadata
package stream_meta is

  -- Takes one AXI4-Stream as input and produces one AXI4-Stream as output.
  -- Input stream may have metadata (ID, Dest, User).
  -- Metadata are assumed constant for a complete frame.
  -- Metadata from the first beat of every frame are extracted and serialized
  -- as a prefix in the output frame.
  -- Output configuration may have any data width.
  -- Backpressure (ready) and framing (last) should be present on both configurations.
  component axi4_stream_meta_packer is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      meta_elements_c : string := "iou";
      endian_c : endian_t := ENDIAN_BIG
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Takes one AXI4-Stream with packed metadata prefix as input and produces
  -- one AXI4-Stream as output.
  -- Extracts metadata from prefix bytes and applies them to all beats of the
  -- output frame.
  -- Input configuration may have any data width.
  -- Backpressure (ready) and framing (last) should be present on both configurations.
  component axi4_stream_meta_unpacker is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      meta_elements_c : string := "iou";
      endian_c : endian_t := ENDIAN_BIG
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

end package;
