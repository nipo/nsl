library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_delay_variable is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    mark_o : out std_ulogic;
    shift_i : in std_ulogic;

    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

-- The GW5A delay line takes its tap either as a whole number or as a
-- target to creep towards, and the two are separate paths through the
-- block:
--
--  * with DYN_DLY_EN true and SDTAP low, DLYSTEP is the tap, straight
--    away and every cycle.  ADAPT_EN false hands that value to the
--    line.
--  * with SDTAP high the block runs a loop of its own: VALUE starts
--    it, and it walks the line one tap per eight edges of the data
--    until the line reaches DLYSTEP.  That path only reaches the line
--    when ADAPT_EN is true, it counts data edges rather than pulses,
--    and it cannot be given a position -- only a direction to creep
--    in.
--
-- A tap per pulse is what delay.pkg promises, so the tap is counted
-- here and handed over whole: the absolute path, with the adaptive
-- loop's two controls held at the values that leave it out of the way.
architecture gowin of input_delay_variable is

  component iodelay
    generic (
      c_static_dly: integer := 0;
      dyn_dly_en: string := "FALSE";
      adapt_en: string := "FALSE"
      );
    port (
      do: out std_logic;
      df: out std_logic;
      di: in std_logic;
      sdtap: in std_logic;
      value: in std_logic;
      dlystep: in std_logic_vector(7 downto 0)
      );
  end component;

  -- Every tap the code reaches, so a walk of the counter is a walk of
  -- the whole line.
  constant tap_count_c: natural := 256;
  signal tap_s: unsigned(7 downto 0);

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if shift_i = '1' then
        if tap_s = tap_count_c - 1 then
          tap_s <= (others => '0');
        else
          tap_s <= tap_s + 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      tap_s <= (others => '0');
    end if;
  end process;

  mark_o <= '1' when tap_s = 0 else '0';

  inst: iodelay
    generic map(
      dyn_dly_en => "TRUE",
      adapt_en => "FALSE"
      )
    port map(
      di => data_i,
      sdtap => '0',
      value => '0',
      dlystep => std_logic_vector(tap_s),
      df => open,
      do => data_o
      );

end architecture;
