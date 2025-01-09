library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_line_coding, nsl_data, work, nsl_dvi;

-- HDMI data stream encoder. Adds HDMI-specific data islands in the
-- DVI stream.
package encoder is

  component hdmi_13_encoder is
    generic(
      vendor_name_c: string := "NSL";
      product_description_c: string := "HDMI Encoder";
      source_type_c: integer := 0
      );
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;

      -- Vertical frame parameters
      v_fp_m1_i : in unsigned;
      v_sync_m1_i : in unsigned;
      v_bp_m1_i : in unsigned;
      v_act_m1_i : in unsigned;

      -- Horizontal frame parameters
      h_fp_m1_i : in unsigned;
      h_sync_m1_i : in unsigned;
      h_bp_m1_i : in unsigned;
      h_act_m1_i : in unsigned;

      -- sync values
      vsync_i : in std_ulogic := '1';
      hsync_i : in std_ulogic := '1';

      -- Start of frame strobe. It happens sol_o is not asserted yet
      sof_o : out std_ulogic;
      -- Start of line strobe. It happens pixel_ready_o is not asserted yet
      sol_o : out std_ulogic;
      -- Asserted every cycle pixel data is taken by encoder
      pixel_ready_o : out std_ulogic;
      pixel_i : in nsl_data.bytestream.byte_string(0 to 2);

      -- Data island insertion option. 
      di_valid_i : in std_ulogic := '0';
      di_ready_o : out std_ulogic;
      di_i : in work.hdmi.data_island_t := work.hdmi.di_null;
      
      tmds_o : out nsl_dvi.dvi.symbol_vector_t
      );
  end component;

  use nsl_data.crc.all;
  use nsl_data.bytestream.all;

  subtype di_bch_t is std_ulogic_vector(0 to 7);
  constant di_bch_params_c : crc_params_t := crc_params(
    poly => x"1c1",
    init => "",
    complement_state => false,
    complement_input => false,
    byte_bit_order => BIT_ORDER_ASCENDING,
    spill_order => EXP_ORDER_ASCENDING,
    byte_order => BYTE_ORDER_INCREASING);

  function di_bch(state: di_bch_t;
                  v: std_ulogic_vector) return di_bch_t;

end package encoder;

package body encoder is

  use nsl_data.crc.all;

  function di_bch(state: di_bch_t;
                  v: std_ulogic_vector) return di_bch_t
  is
    variable s : crc_state_t := crc_load(di_bch_params_c, state);
  begin
    for i in v'low to v'high
    loop
      s := crc_update(di_bch_params_c, s, v(i));
    end loop;

    return crc_spill_vector(di_bch_params_c, s);
  end function;

end package body;
