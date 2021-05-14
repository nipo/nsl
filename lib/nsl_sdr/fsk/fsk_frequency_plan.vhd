library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity fsk_frequency_plan is
  generic (
    -- Sampling frequency
    fs_c : real;
    -- Channel 0 center frequency
    channel_0_center_hz_c : real;
    -- Channel separation
    channel_separation_hz_c : real;
    -- Channel count
    channel_count_c : integer;
    -- Fd for 0
    fd_0_hz_c : real;
    -- Fd increment for each symbol increment
    fd_separation_hz_c : real
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Current channel. Max channel number is defined by dynamic
    -- range of channel_i.
    channel_i : in unsigned(nsl_math.arith.log2(channel_count_c)-1 downto 0);

    -- Current symbol
    symbol_i : in unsigned;
    
    -- Instantaneous phase increment for this cycle. Because of
    -- nyquist, (phase_increment_i'left downto 1) should not ever
    -- have a bit set.
    phase_increment_o : out ufixed
    );
end entity;    

architecture beh of fsk_frequency_plan is

  constant dt_bit_count : integer := phase_increment_o'length;
  constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
  subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);
  
  function table_precalc(fs, c0, cs, fd0, fds : real;
                         channel_count, symbol_count : integer)
    return real_vector
  is
    variable ret : real_vector(0 to channel_count * symbol_count - 1);
    variable freq, entry : real;
  begin
    each_channel: for chan in 0 to channel_count - 1
    loop
      each_symbol: for sym in 0 to symbol_count - 1
      loop
        freq := c0 + cs * real(chan) + fd0 + fds * real(sym);
        entry := freq / fs;
        ret(chan * symbol_count + sym) := entry;
      end loop;
    end loop;

    return ret;
  end function;

  signal s_address : unsigned(channel_i'length + symbol_i'length - 1 downto 0);
  
begin

  s_address <= channel_i & symbol_i;
  
  storage: nsl_memory.rom_fixed.rom_ufixed
    generic map(
      values_c => table_precalc(fs_c,
                                channel_0_center_hz_c,
                                channel_separation_hz_c,
                                fd_0_hz_c,
                                fd_separation_hz_c,
                                channel_count_c,
                                2 ** symbol_i'length
                                )
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      address_i => s_address,
      value_o => phase_increment_o
      );

end architecture;

