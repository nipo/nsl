library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking, nsl_uart;
use nsl_uart.serdes.all;

-- Ethernet magnetics pin mapping finder.
--
-- Bring-up helper for connecting ethernet magnetics straight to FPGA
-- pins: it tells which pins carry the link partner's signal, without
-- needing the module schematic.
--
-- All eight PMOD data pins are sampled as single-ended LVCMOS33
-- inputs.  Each pair candidate gets a weak pull-up on one leg and a
-- weak pull-down on the other (see pinout.cst): a transformer winding
-- is a DC short between the two legs, so they settle near mid-supply,
-- where the partner's signal crosses the input threshold.  Line
-- transitions then show up single-ended on both legs of a pair, in
-- opposite senses.
--
-- Edge counts are printed once per second on the UART, 8
-- space-separated 6-digit hex fields, in pinout.cst probe index
-- order.  The pair showing sustained activity is the receive pair.
--
-- Beware a partner with auto-MDIX: as long as no link is
-- established, it swaps the pair it transmits on every few tens of
-- milliseconds, so two different pairs look active within a one
-- second window.  Only the pair still active once a link is up is
-- the real receive pair.
entity boundary is
  port (
    clk_i: in std_ulogic;
    probe_i: in std_ulogic_vector(0 to 7);
    uart_tx_o: out std_ulogic;
    uart_rx_i: in std_ulogic;
    done_led_o: out std_ulogic
    );
end boundary;

architecture arch of boundary is

  constant clock_hz_c: integer := 50000000;
  constant baudrate_c: integer := 115200;
  constant divisor_c: unsigned(15 downto 0)
    := to_unsigned(clock_hz_c / baudrate_c - 1, 16);

  signal clock_s, reset_n_s: std_ulogic;
  signal rising_s, falling_s: std_ulogic_vector(0 to 7);
  signal ready_s, uart_valid_s: std_ulogic;
  signal uart_data_s: std_ulogic_vector(7 downto 0);

  subtype count_t is unsigned(23 downto 0);
  type count_vector_t is array(0 to 7) of count_t;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_EMIT_HEX,
    ST_EMIT_SEP,
    ST_EMIT_CR,
    ST_EMIT_LF
    );

  type regs_t is
  record
    state: state_t;
    counter: count_vector_t;
    snapshot: count_vector_t;
    second: integer range 0 to clock_hz_c - 1;
    pin: integer range 0 to 7;
    nib: integer range 0 to 5;
  end record;

  signal r, rin: regs_t;

  function nibble_of(v: count_t; idx: integer range 0 to 5) return unsigned
  is
  begin
    case idx is
      when 0 => return v(23 downto 20);
      when 1 => return v(19 downto 16);
      when 2 => return v(15 downto 12);
      when 3 => return v(11 downto 8);
      when 4 => return v(7 downto 4);
      when 5 => return v(3 downto 0);
    end case;
  end function;

  function to_hex_ascii(n: unsigned(3 downto 0)) return std_ulogic_vector
  is
  begin
    if n < 10 then
      return std_ulogic_vector(resize(n, 8) + character'pos('0'));
    else
      return std_ulogic_vector(resize(n, 8) + character'pos('a') - 10);
    end if;
  end function;

begin

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  por: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => reset_n_s
      );

  probes: for i in 0 to 7 generate
    sampler: nsl_clocking.async.async_input
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        data_i => probe_i(i),
        data_o => open,
        rising_o => rising_s(i),
        falling_o => falling_s(i)
        );
  end generate;

  regs: process(clock_s, reset_n_s)
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;
    if reset_n_s = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, rising_s, falling_s, ready_s)
  begin
    rin <= r;

    for i in 0 to 7 loop
      if (rising_s(i) = '1' or falling_s(i) = '1')
        and r.counter(i) /= x"ffffff" then
        rin.counter(i) <= r.counter(i) + 1;
      end if;
    end loop;

    if r.second /= 0 then
      rin.second <= r.second - 1;
    end if;

    case r.state is
      when ST_RESET =>
        rin.second <= clock_hz_c - 1;
        rin.counter <= (others => (others => '0'));
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if r.second = 0 then
          rin.second <= clock_hz_c - 1;
          rin.snapshot <= r.counter;
          rin.counter <= (others => (others => '0'));
          rin.pin <= 0;
          rin.nib <= 0;
          rin.state <= ST_EMIT_HEX;
        end if;

      when ST_EMIT_HEX =>
        if ready_s = '1' then
          if r.nib /= 5 then
            rin.nib <= r.nib + 1;
          else
            rin.nib <= 0;
            rin.state <= ST_EMIT_SEP;
          end if;
        end if;

      when ST_EMIT_SEP =>
        if ready_s = '1' then
          if r.pin /= 7 then
            rin.pin <= r.pin + 1;
            rin.state <= ST_EMIT_HEX;
          else
            rin.state <= ST_EMIT_CR;
          end if;
        end if;

      when ST_EMIT_CR =>
        if ready_s = '1' then
          rin.state <= ST_EMIT_LF;
        end if;

      when ST_EMIT_LF =>
        if ready_s = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  uart: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => PARITY_NONE
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      divisor_i => divisor_c,
      uart_o => uart_tx_o,
      data_i => uart_data_s,
      ready_o => ready_s,
      valid_i => uart_valid_s
      );

  moore: process(r)
  begin
    uart_valid_s <= '0';
    uart_data_s <= (others => '0');

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_EMIT_HEX =>
        uart_valid_s <= '1';
        uart_data_s <= to_hex_ascii(nibble_of(r.snapshot(r.pin), r.nib));

      when ST_EMIT_SEP =>
        uart_valid_s <= '1';
        uart_data_s <= x"20";

      when ST_EMIT_CR =>
        uart_valid_s <= '1';
        uart_data_s <= x"0d";

      when ST_EMIT_LF =>
        uart_valid_s <= '1';
        uart_data_s <= x"0a";
    end case;
  end process;

  done_led_o <= '1' when r.second > clock_hz_c / 2 else '0';

end arch;
