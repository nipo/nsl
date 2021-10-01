library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_line_coding;
use work.spdif.all;
use work.serdes.all;

entity spdif_serializer is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;

    symbol_i : in spdif_symbol_t;
    ready_o : out std_ulogic;

    data_o : out std_ulogic
    );
end entity;

architecture beh of spdif_serializer is

  type regs_t is
  record
    shreg: std_ulogic_vector(0 to 7);
    shreg_to_go: natural range 0 to 7;
  end record;

  signal r, rin: regs_t;
  
begin

  nrzi: nsl_line_coding.nrzi.nrzi_transmitter
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      valid_i => tick_i,
      bit_i => r.shreg(0),
      data_o => data_o
      );
  
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.shreg_to_go <= 0;
    end if;
  end process;

  transition: process(r, symbol_i, tick_i) is
  begin
    rin <= r;

    if tick_i = '1' then
      if r.shreg_to_go /= 0 then
        rin.shreg <= r.shreg(1 to r.shreg'right) & '-';
        rin.shreg_to_go <= r.shreg_to_go - 1;
      else
        case symbol_i is
          when SPDIF_SYNC_B =>
            rin.shreg <= PRE_B;
            rin.shreg_to_go <= 7;
          when SPDIF_SYNC_M =>
            rin.shreg <= PRE_M;
            rin.shreg_to_go <= 7;
          when SPDIF_SYNC_W =>
            rin.shreg <= PRE_W;
            rin.shreg_to_go <= 7;
          when SPDIF_0 =>
            rin.shreg(0 to 1) <= BIT_0;
            rin.shreg_to_go <= 1;
          when SPDIF_1 =>
            rin.shreg(0 to 1) <= BIT_1;
            rin.shreg_to_go <= 1;
        end case;
      end if;
    end if;
  end process;

  ready_o <= tick_i when r.shreg_to_go = 0 else '0';

end architecture;

