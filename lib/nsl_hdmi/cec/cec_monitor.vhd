library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_line_coding;
use work.cec.all;

entity cec_monitor is
  generic(
    clock_i_hz_c: natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    cec_i : in std_ulogic;

    busy_o: out std_ulogic;
    same_init_cts_o: out std_ulogic;
    new_init_cts_o: out std_ulogic;
    retry_cts_o: out std_ulogic
    );
end entity;

architecture beh of cec_monitor is

  type regs_t is
  record
    
    free_bit_count: natural range 0 to 7;
    symbol: spdif_symbol_t;
    valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal s_nrzi_bit, s_nrzi_valid : std_ulogic;
  
begin

  nrzi: nsl_line_coding.nrzi.nrzi_receiver_recovery
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      run_length_limit_c => 3,
      signal_hz_c => data_rate_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => data_i,

      bit_o => s_nrzi_bit,
      valid_o => s_nrzi_valid,

      tick_o => ui_tick_o
      );
  
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.synced <= false;
    end if;
  end process;

  transition: process(r, s_nrzi_valid, s_nrzi_bit) is
  begin
    rin <= r;

    rin.valid <= '0';
    
    if s_nrzi_valid = '1' then
      rin.shreg <= r.shreg(1 to r.shreg'right) & s_nrzi_bit;
      if r.shreg = PRE_B then
        rin.sym_to_go <= 7;
        rin.valid <= '1';
        rin.synced <= true;
        rin.symbol <= SPDIF_SYNC_B;
      elsif r.shreg = PRE_M then
        rin.sym_to_go <= 7;
        rin.valid <= '1';
        rin.synced <= true;
        rin.symbol <= SPDIF_SYNC_M;
      elsif r.shreg = PRE_W then
        rin.sym_to_go <= 7;
        rin.valid <= '1';
        rin.synced <= true;
        rin.symbol <= SPDIF_SYNC_W;
      elsif r.sym_to_go /= 0 then
        rin.sym_to_go <= r.sym_to_go - 1;
      elsif r.shreg(0 to 1) = BIT_0 then
        rin.valid <= '1';
        rin.sym_to_go <= 1;
        rin.symbol <= SPDIF_0;
      elsif r.shreg(0 to 1) = BIT_1 then
        rin.valid <= '1';
        rin.sym_to_go <= 1;
        rin.symbol <= SPDIF_1;
      else
        rin.synced <= false;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    if r.synced then
      synced_o <= '1';
    else
      synced_o <= '0';
    end if;

    valid_o <= r.valid;
    symbol_o <= r.symbol;
  end process;
  
end architecture;

