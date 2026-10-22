library ieee;
use ieee.std_logic_1164.all;

-- UART line signals.
package uart is

  -- Signals emitted by one end of a UART link. The same record is
  -- used for both directions, so connecting two ends is a plain
  -- cross-assignment of their outputs to each other's inputs, whether
  -- ends are DTE or DCE.
  --
  -- All control fields are positive logic: '1' means asserted.
  -- Inversion to RS-232 or TTL wire polarity happens at the pin.
  type uart_signals_t is
  record
    -- Serial data, idle '1'.
    data: std_ulogic;
    -- RTS when emitted by a DTE, CTS when emitted by a DCE.
    rts: std_ulogic;
    -- DTR when emitted by a DTE, DSR when emitted by a DCE.
    dtr: std_ulogic;
    -- Only meaningful when emitted by a DCE.
    dcd: std_ulogic;
    -- Only meaningful when emitted by a DCE.
    ri: std_ulogic;
  end record;

  -- Idle line, all controls deasserted.
  constant uart_idle_c : uart_signals_t := (
    data => '1',
    rts => '0',
    dtr => '0',
    dcd => '0',
    ri => '0'
    );

  -- What a DTE should see when no DCE controls are wired: idle line,
  -- always clear to send and ready, no carrier, no ring.
  constant uart_dce_absent_c : uart_signals_t := (
    data => '1',
    rts => '1',
    dtr => '1',
    dcd => '0',
    ri => '0'
    );

end package;
