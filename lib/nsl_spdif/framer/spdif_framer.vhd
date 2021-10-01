library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.spdif.all;
use work.serdes.all;
use work.framer.all;
  
entity spdif_framer is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    block_start_i : in std_ulogic;
    channel_i : in std_ulogic;
    frame_i : in frame_t;
    ready_o : out std_ulogic;
    
    symbol_o : out spdif_symbol_t;
    ready_i : in std_ulogic
    );
end entity;

architecture beh of spdif_framer is

  type state_t is (
    ST_RESET,
    ST_TAKE,
    ST_PRE,
    ST_DATA,
    ST_PAR
    );

  type regs_t is
  record
    state: state_t;
    shreg: std_ulogic_vector(0 to 26);
    channel, par, block_start: std_ulogic;
    shreg_left: integer range 0 to 26;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, block_start_i, frame_i, ready_i, channel_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAKE;

      when ST_TAKE =>
        rin.shreg <= nsl_data.endian.bitswap(std_ulogic_vector(frame_i.aux))
                     & nsl_data.endian.bitswap(std_ulogic_vector(frame_i.audio))
                     & frame_i.invalid & frame_i.user & frame_i.channel_status;
        rin.channel <= channel_i;
        rin.shreg_left <= 26;
        rin.block_start <= block_start_i;
        rin.state <= ST_PRE;
        rin.par <= '0';

      when ST_PRE =>
        if ready_i = '1' then
          rin.state <= ST_DATA;
        end if;

      when ST_DATA =>
        if ready_i = '1' then
          rin.shreg <= r.shreg(1 to 26) & '-';
          rin.par <= r.shreg(0) xor r.par;
          if r.shreg_left = 0 then
            rin.state <= ST_PAR;
          else
            rin.shreg_left <= r.shreg_left - 1;
          end if;
        end if;

      when ST_PAR =>
        if ready_i = '1' then
          rin.state <= ST_TAKE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    symbol_o <= SPDIF_1;
    ready_o <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_TAKE =>
        ready_o <= '1';

      when ST_PRE =>
        if r.block_start = '1' then
          symbol_o <= SPDIF_SYNC_B;
        elsif r.channel = '0' then
          symbol_o <= SPDIF_SYNC_M;
        else
          symbol_o <= SPDIF_SYNC_W;
        end if;

      when ST_DATA =>
        if r.shreg(0) = '1' then
          symbol_o <= SPDIF_1;
        else
          symbol_o <= SPDIF_0;
        end if;

      when ST_PAR =>
        if r.par = '1' then
          symbol_o <= SPDIF_1;
        else
          symbol_o <= SPDIF_0;
        end if;
    end case;

  end process;
  
end architecture;
