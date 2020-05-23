library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

entity ws_2812_driver is
  generic(
    color_order : string := "GRB";
    clk_freq_hz : natural;
    error_ns : natural := 150;
    t0h_ns : natural := 350;
    t0l_ns : natural := 1360;
    t1h_ns : natural := 1360;
    t1l_ns : natural := 350
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    led_o : out std_ulogic;

    color_i : in nsl_color.rgb.rgb24;
    valid_i : in  std_ulogic;
    ready_o : out std_ulogic;
    last_i : in std_ulogic
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


  constant bit_ns : natural := ((t0l_ns + t0h_ns) + (t1l_ns + t1h_ns)) / 2;
  constant bit_cycles : natural := (bit_ns + error_ns) / (error_ns * 2);
  constant cycle_time_ns : natural := bit_ns / bit_cycles;

  constant ws_cycle_hz : natural := 1000000000 / cycle_time_ns;
  constant ws_cycle_ticks : natural := (clk_freq_hz + ws_cycle_hz - 1) / ws_cycle_hz;

  constant t0h_cycles : natural := (t0h_ns + cycle_time_ns / 2) / cycle_time_ns;
  constant t1h_cycles : natural := (t1h_ns + cycle_time_ns / 2) / cycle_time_ns;

  constant ws_high_cycles : natural := t0h_cycles;
  constant ws_bit_cycles : natural := t1h_cycles - t0h_cycles;
  constant ws_low_cycles : natural := bit_cycles - t1h_cycles;

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
    divisor : natural range 0 to ws_cycle_ticks - 1;
    cycle_counter : natural range 0 to ws_reset_cycles - 1;
    bitno : natural range 0 to 23;
    last : boolean;
    state : state_t;
    shreg : std_ulogic_vector(23 downto 0);
  end record;

  signal r, rin : regs_t;
  
begin

  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, color_i, valid_i, last_i)
  begin
    rin <= r;

    rin.divisor <= ws_cycle_ticks - 1;

    case r.state is
      when RESET =>
        rin.state <= WAITING;

      when WAITING =>
        if valid_i = '1' then
          rin.shreg <= nsl_color.rgb.rgb24_to_suv(
            color => color_i,
            lsb_right => true,
            color_order => color_order);
          rin.bitno <= 23;
          rin.last <= last_i = '1';

          rin.cycle_counter <= ws_high_cycles - 1;
          rin.state <= SHIFTING_HIGH;
        end if;

      when SHIFTING_HIGH =>
        if r.divisor /= 0 then
          rin.divisor <= r.divisor - 1;
        elsif r.cycle_counter /= 0 then
          rin.cycle_counter <= r.cycle_counter - 1;
        else
          rin.cycle_counter <= ws_bit_cycles - 1;
          rin.state <= SHIFTING_BIT;
        end if;

      when SHIFTING_BIT =>
        if r.divisor /= 0 then
          rin.divisor <= r.divisor - 1;
        elsif r.cycle_counter /= 0 then
          rin.cycle_counter <= r.cycle_counter - 1;
        else
          rin.cycle_counter <= ws_low_cycles - 1;
          rin.state <= SHIFTING_LOW;
        end if;

      when SHIFTING_LOW =>
        if r.divisor /= 0 then
          rin.divisor <= r.divisor - 1;
        elsif r.cycle_counter /= 0 then
          rin.cycle_counter <= r.cycle_counter - 1;
        elsif r.bitno /= 0 then
          rin.shreg <= r.shreg(r.shreg'left-1 downto 0) & '-';
          rin.bitno <= r.bitno - 1;
          rin.cycle_counter <= ws_high_cycles - 1;
          rin.state <= SHIFTING_HIGH;
        elsif r.last then
          rin.state <= FLUSHING;
          rin.cycle_counter <= ws_reset_cycles - 1;
        else
          rin.state <= WAITING;
        end if;

      when FLUSHING =>
        if r.divisor /= 0 then
          rin.divisor <= r.divisor - 1;
        elsif r.cycle_counter /= 0 then
          rin.cycle_counter <= r.cycle_counter - 1;
        else
          rin.state <= WAITING;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    ready_o <= '0';
    led_o <= '0';

    case r.state is
      when WAITING =>
        ready_o <= '1';

      when SHIFTING_HIGH =>
        led_o <= '1';

      when SHIFTING_BIT =>
        led_o <= r.shreg(r.shreg'left);

      when others =>
        null;
    end case;
  end process;
  
end;

