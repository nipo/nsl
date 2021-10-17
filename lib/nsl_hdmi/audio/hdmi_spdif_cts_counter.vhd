library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_spdif_cts_counter is
  generic(
    audio_clock_divisor_c: natural := 4096
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    cts_o : out unsigned(19 downto 0);
    cts_send_o : out std_ulogic;

    spdif_tick_i : in std_ulogic
    );
end entity;

architecture beh of hdmi_spdif_cts_counter is

  type regs_t is
  record
    audio_tick_divisor: natural range 0 to audio_clock_divisor_c-1;
    cts, cts_ctr: unsigned(19 downto 0);
  end record;
  
  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cts <= (others => '0');
      r.cts_ctr <= (others => '0');
    end if;
  end process;

  transition: process(r, spdif_tick_i) is
  begin
    rin <= r;

    rin.cts_ctr <= r.cts_ctr + 1;

    if spdif_tick_i = '1' then
      if r.audio_tick_divisor = 0 then
        rin.audio_tick_divisor <= audio_clock_divisor_c-1;
        rin.cts <= r.cts_ctr;
        rin.cts_ctr <= to_unsigned(1, rin.cts_ctr'length);
      else
        rin.audio_tick_divisor <= r.audio_tick_divisor - 1;
      end if;
    end if;
  end process;

  cts_o <= r.cts;
  cts_send_o <= '1' when r.audio_tick_divisor = 0 else '0';

end architecture;
