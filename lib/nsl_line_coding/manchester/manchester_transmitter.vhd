library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity manchester_transmitter is
  generic (
    clock_i_hz_c : natural;
    signal_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ready_o : out std_ulogic;
    valid_i : in std_ulogic;
    bit_i : in std_ulogic;

    active_o : out std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture beh of manchester_transmitter is

  constant half_bit_c : natural := clock_i_hz_c / (2 * signal_hz_c);

  type state_t is (
    ST_IDLE,
    ST_FIRST_HALF,
    ST_SECOND_HALF
    );

  type regs_t is
  record
    state: state_t;
    counter: natural range 0 to half_bit_c - 1;
    value: std_ulogic;
    line: std_ulogic;
    ready: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  assert clock_i_hz_c = half_bit_c * 2 * signal_hz_c
    report "clock_i_hz_c must be an integer multiple of 2 * signal_hz_c"
    severity failure;

  assert half_bit_c >= 2
    report "clock_i_hz_c must be at least 4 * signal_hz_c"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.counter <= 0;
      r.value <= '0';
      r.line <= '0';
      r.ready <= '1';
    end if;
  end process;

  transition: process(r, valid_i, bit_i) is
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        if valid_i = '1' then
          rin.state <= ST_FIRST_HALF;
          rin.counter <= half_bit_c - 1;
          rin.value <= bit_i;
          rin.line <= not bit_i;
          rin.ready <= '0';
        end if;

      when ST_FIRST_HALF =>
        if r.counter /= 0 then
          rin.counter <= r.counter - 1;
        else
          rin.state <= ST_SECOND_HALF;
          rin.counter <= half_bit_c - 1;
          rin.line <= r.value;
        end if;

      when ST_SECOND_HALF =>
        if r.counter /= 0 then
          rin.counter <= r.counter - 1;
          if r.counter = 1 then
            rin.ready <= '1';
          end if;
        else
          -- Last cycle of the cell, ready is asserted, interface is
          -- sampled here.
          if valid_i = '1' then
            rin.state <= ST_FIRST_HALF;
            rin.counter <= half_bit_c - 1;
            rin.value <= bit_i;
            rin.line <= not bit_i;
            rin.ready <= '0';
          else
            rin.state <= ST_IDLE;
            rin.line <= '0';
            rin.ready <= '1';
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    ready_o <= r.ready;
    data_o <= r.line;

    case r.state is
      when ST_IDLE =>
        active_o <= '0';
      when others =>
        active_o <= '1';
    end case;
  end process;

end architecture;
