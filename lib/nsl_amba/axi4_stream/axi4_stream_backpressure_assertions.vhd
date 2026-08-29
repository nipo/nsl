library ieee;
use ieee.std_logic_1164.all;

library work;
use work.axi4_stream.all;

-- Asserts that the monitored interface never backpressures: once
-- reset is released and the grace period has elapsed, ready must be
-- high on every clock cycle where enable_i is set.  This enforces the
-- ingress contract of line-rate components, where the data source
-- cannot be stalled.
entity axi4_stream_backpressure_assertions is
  generic(
    config_c : config_t;
    prefix_c : string := "AXIS";
    grace_cycles_c : natural := 0;
    severity_c : severity_level := failure
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    bus_i : in bus_t
    );
end entity;

architecture beh of axi4_stream_backpressure_assertions is
begin

  assert config_c.has_ready
    report prefix_c & " backpressure assertions on an interface without ready"
    severity failure;

  monitor: process is
    variable grace_left : natural := grace_cycles_c;
  begin
    wait until rising_edge(clock_i);

    if reset_n_i = '0' then
      grace_left := grace_cycles_c;
    elsif grace_left /= 0 then
      grace_left := grace_left - 1;
    elsif enable_i = '1' then
      assert is_ready(config_c, bus_i.s)
        report prefix_c & " backpressure: ready deasserted at "
        & time'image(now)
        severity severity_c;
    end if;
  end process;

end architecture;
