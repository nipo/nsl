library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity ws_2812_driver is
  generic(
    clk_freq_hz : natural;
    cycle_time_ns : natural := 208
    );
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_data : out std_ulogic;

    p_led : in signalling.color.rgb24;
    p_valid : in  std_ulogic;
    p_ready : out std_ulogic;
    p_last : in std_ulogic
    );
end entity;

architecture rtl of ws_2812_driver is

  -- Datasheet describes timings in terms of min/max times for a given
  -- bit, but various reverse engineering efforts (and some official
  -- WS datasheets) indicate WS281x chips have an internal RC and
  -- timings are actually driven by internal sampling of data
  -- line. Let's rewrite the datasheet:
  --
  --  Bit valued '1':  T1H with din = '1', T1L with din = '0'
  --  Bit valued '0':  T0H with din = '1', T0L with din = '0'
  --
  --  HIGH : din = '1', BIT : din = bit, LOW : din = '0'
  --
  -- T1H = T_HIGH + T_BIT
  -- T1L = T_LOW
  -- T0H = T_HIGH
  -- T0L = T_BIT + T_LOW
  --
  -- These timings should actually be counted in terms of cycles. For
  -- any level value to be reliably detected, it should be at least 2
  -- cycles. Then cycle lengths are:
  --
  -- T_HIGH >= 2 cycles
  -- T_BIT >= 2 cycles
  -- T_LOW >= 2 cycles (only if T_BIT was spent high)
  --
  --       |        WS281x bit          |
  --       |  HIGH      BIT      LOW    |
  --       |        |         |         | ...
  --        __________________           _...
  --  _____/        \_________\_________/ ...
  --
  -- HIGH: High time
  -- BIT: Bit value time
  -- LOW: Low time
  --
  -- Reset timing (time between lines) is, depending on datasheets, at
  -- least 64 cycles.

  
  constant ws_cycle_hz : natural := 1000000000 / cycle_time_ns;
  constant ws_cycle_ticks : natural := (clk_freq_hz + ws_cycle_hz - 1) / ws_cycle_hz;
  constant ws_high_cycles : natural := 2;
  constant ws_bit_cycles : natural := 2;
  constant ws_low_cycles : natural := 2;
  constant ws_reset_cycles : natural := 64;

  type state_t is (
    RESET,
    WAITING,
    SHIFTING_HIGH,
    SHIFTING_BIT,
    SHIFTING_LOW,
    FLUSHING
    );
  
  type regs_t is
  record
    timer : natural range 0 to ws_cycle_ticks * ws_reset_cycles - 1;
    bitno : natural range 0 to 23;
    last : boolean;
    state : state_t;
    shreg : std_ulogic_vector(23 downto 0);
  end record;

  signal r, rin : regs_t;
  
begin

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_led, p_valid, p_last)
  begin
    rin <= r;

    case r.state is
      when RESET =>
        rin.timer <= 0;
        rin.state <= WAITING;

      when WAITING =>
        if p_valid = '1' then
          rin.shreg <= std_ulogic_vector(
            to_unsigned(p_led.g, 8)
            & to_unsigned(p_led.r, 8)
            & to_unsigned(p_led.b, 8)
            );
          rin.bitno <= 23;
          rin.last <= p_last = '1';

          rin.timer <= ws_cycle_ticks * ws_high_cycles - 1;
          rin.state <= SHIFTING_HIGH;
        end if;

      when SHIFTING_HIGH =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= ws_cycle_ticks * ws_bit_cycles - 1;
          rin.state <= SHIFTING_BIT;
        end if;

      when SHIFTING_BIT =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= ws_cycle_ticks * ws_low_cycles - 1;
          rin.state <= SHIFTING_LOW;
        end if;

      when SHIFTING_LOW =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        elsif r.bitno /= 0 then
          rin.shreg <= r.shreg(r.shreg'left-1 downto 0) & '-';
          rin.bitno <= r.bitno - 1;
          rin.timer <= ws_cycle_ticks * ws_high_cycles - 1;
          rin.state <= SHIFTING_HIGH;
        elsif r.last then
          rin.state <= FLUSHING;
          rin.timer <= ws_cycle_ticks * ws_reset_cycles - 1;
        else
          rin.state <= WAITING;
        end if;

      when FLUSHING =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= WAITING;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    p_ready <= '0';
    p_data <= '0';

    case r.state is
      when WAITING =>
        p_ready <= '1';

      when SHIFTING_HIGH =>
        p_data <= '1';

      when SHIFTING_BIT =>
        p_data <= r.shreg(r.shreg'left);

      when others =>
        null;
    end case;
  end process;
  
end;

