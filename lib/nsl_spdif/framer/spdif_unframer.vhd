library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.spdif.all;
use work.serdes.all;
use work.framer.all;
  
entity spdif_unframer is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    
    symbol_i : in spdif_symbol_t;
    synced_i : in std_ulogic;
    valid_i : in std_ulogic;

    synced_o : out std_ulogic;
    block_start_o : out std_ulogic;
    channel_o : out std_ulogic;
    frame_o : out frame_t;
    parity_ok_o : out std_ulogic;
    valid_o : out std_ulogic
    );
end entity;

architecture beh of spdif_unframer is

  type state_t is (
    ST_RESET,
    ST_PRE,
    ST_DATA,
    ST_PAR,
    ST_PUT
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

  transition: process(r, symbol_i, synced_i, valid_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_PRE;

      when ST_PRE =>
        if valid_i = '1' then
          rin.shreg_left <= 26;
          rin.par <= '0';
          if symbol_i = SPDIF_SYNC_B then
            rin.block_start <= '1';
            rin.channel <= '0';
            rin.state <= ST_DATA;
          elsif symbol_i = SPDIF_SYNC_M then
            rin.block_start <= '0';
            rin.channel <= '0';
            rin.state <= ST_DATA;
          elsif symbol_i = SPDIF_SYNC_W then
            rin.block_start <= '0';
            rin.channel <= '1';
            rin.state <= ST_DATA;
          end if;
        end if;

      when ST_DATA =>
        if valid_i = '1' then
          if r.shreg_left = 0 then
            rin.state <= ST_PAR;
          else
            rin.shreg_left <= r.shreg_left - 1;
          end if;

          if symbol_i = SPDIF_0 then
            rin.shreg <= r.shreg(1 to 26) & "0";
          elsif symbol_i = SPDIF_1 then
            rin.shreg <= r.shreg(1 to 26) & "1";
            rin.par <= not r.par;
          else
            rin.shreg <= r.shreg(1 to 26) & "-";
            rin.state <= ST_PRE;
          end if;
        end if;

      when ST_PAR =>
        if valid_i = '1' then
          if symbol_i = SPDIF_0 then
            rin.state <= ST_PUT;
          elsif symbol_i = SPDIF_1 then
            rin.par <= not r.par;
            rin.state <= ST_PUT;
          else
            rin.state <= ST_PRE;
          end if;
        end if;

      when ST_PUT =>
        rin.state <= ST_PRE;
    end case;
  end process;

  synced_o <= synced_i;

  moore: process(r) is
  begin
    if r.state = ST_PUT then
      valid_o <= '1';
    else
      valid_o <= '0';
    end if;
    
    block_start_o <= r.block_start;
    frame_o.aux <= unsigned(nsl_data.endian.bitswap(r.shreg(0 to 3)));
    frame_o.audio <= unsigned(nsl_data.endian.bitswap(r.shreg(4 to 23)));
    frame_o.invalid <= r.shreg(24);
    frame_o.user <= r.shreg(25);
    frame_o.channel_status <= r.shreg(26);
    channel_o <= r.channel;
    parity_ok_o <= r.par;
  end process;
  
end architecture;
