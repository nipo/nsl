library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Coding scheme from A. X. Widmer and P. A. Franaszek, IBM
--
-- See IBM Journal of Research & Development Vol. 27 No. 5 pp. 440-451
-- "A DC-Balanced, Partitioned-Block, 8B/ 10B Transmission Code" or
-- Patent US 4,486,739 "Byte-oriented DC-balanced 8B/10B partitioned
-- block transmission code" for reference.

-- This package exposes 8b/10b codec as streaming components.  If you
-- require procedural implementation, you may import ibm_8b10b_logic,
-- ibm_8b10b_spec or ibm_8b10b_table packages.  They have various
-- complexities and underlying features.  See each package for
-- details.

package ibm_8b10b is

  -- Data word and code word with LSB on the right. This is contrary
  -- of IBMRD and patent publications where all figures and tables
  -- have LSB on the left. NSL is biased to LSB-first, LSB on right
  -- notation.
  --
  -- From IBMRD: "The ten encoded lines abcdeifghj normally interface
  -- with the serializer; the a-bit must be transmitted first and j
  -- last."
  --
  -- Beware some foreign implementations get the bit order wrong. This
  -- has consequences for constraints like one described in "The
  -- singular comma" paragraph on page 446 of IBMRD. Bug is on side of
  -- other implementors.

  -- HGFEDCBA
  subtype data_word is std_ulogic_vector(7 downto 0);
  -- jhgfiedcba, transmit LSB first (from index 0)
  subtype code_word is std_ulogic_vector(9 downto 0);

  -- Control word expressed as pair of integers. Suitable for matching
  -- Kx.y notation.
  function control(x : integer range 0 to 31;
                   y : integer range 0 to 7)
    return data_word;

  -- Whether given x.y matches an existing/valid control code.
  function control_exists(x : integer range 0 to 31;
                          y : integer range 0 to 7)
    return boolean;

  -- Named constants for existing control codes.
  -- idle
  constant K23_7 : data_word := control(23, 7);
  -- idle
  constant K27_7 : data_word := control(27, 7);
  constant K28_0 : data_word := control(28, 0);
  -- is comma
  constant K28_1 : data_word := control(28, 1);
  constant K28_2 : data_word := control(28, 2);
  constant K28_3 : data_word := control(28, 3);
  constant K28_4 : data_word := control(28, 4);
  -- is comma, 50% transition
  constant K28_5 : data_word := control(28, 5);
  constant K28_6 : data_word := control(28, 6);
  -- is comma, repetition yields alternative RL5, forbidden
  constant K28_7 : data_word := control(28, 7);
  -- idle
  constant K29_7 : data_word := control(29, 7);
  constant K30_7 : data_word := control(30, 7);

  -- 8B/10B streaming encoder. Disparity is internal, it is reset on
  -- block reset. Input to output latency is implementation specific.
  --
  -- Available implementations (metrics on xc6s):
  -- - rom
  --   Usage: 1024 x 11 ROM
  --   Performance: ~310 MHz
  --
  -- - logic
  --   Usage: 32 FF, 42 LUTs
  --   Performance: ~250 MHz
  --
  -- - lut
  --   Usage: 11 FF, 86 LUTs
  --   Performance: ~130 MHz
  --
  -- - spec
  --   Usage: 12 FF, 18 LUTs
  --   Performance: ~180 MHz
  component ibm_8b10b_encoder
    generic(
      -- logic, rom, spec, lut
      implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in data_word;
      control_i : in std_ulogic;

      data_o : out code_word
      );
  end component;

  -- 8B/10B streaming decoder. Disparity is internal, it is reset on
  -- block reset. Input to output latency is implementation specific.
  --
  -- Available implementations (metrics on xc6s):
  -- - rom
  --   Usage: 1024 x 14 ROM, 13 FF, 3 LUTs
  --   Performance: ~260 MHz
  --
  -- - logic / strict = false
  --   Usage: 51 FF, 46 LUTs
  --   Performance: ~260 MHz
  --
  -- - logic / strict = true
  --   Usage: 61 FF, 70 LUTs
  --   Performance: ~230 MHz
  --
  -- - lut
  --   Usage: 13 FF, 100 LUTs
  --   Performance: ~120 MHz
  --
  -- - spec
  --   Usage: 13 FF, 45 LUTs
  --   Performance: ~170 MHz
  component ibm_8b10b_decoder
    generic(
      -- logic, rom, spec, lut
      implementation_c : string := "logic";
      -- Whether all disparity errors are reported without exception.
      strict_c : boolean := true
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in code_word;

      data_o : out data_word;
      control_o : out std_ulogic;
      code_error_o : out std_ulogic;
      disparity_error_o : out std_ulogic
      );
  end component;

end package;

package body ibm_8b10b is

  function control(x : integer range 0 to 31;
                   y : integer range 0 to 7)
    return data_word
  is
  begin
    return data_word(std_ulogic_vector(to_unsigned(y, 3) & to_unsigned(x, 5)));
  end function;

  function control_exists(x : integer range 0 to 31;
                          y : integer range 0 to 7)
    return boolean
  is
  begin
    return x = 28 or (y = 7 and (x = 23 or (x >= 27 and x <= 30)));
  end function;

end package body;
