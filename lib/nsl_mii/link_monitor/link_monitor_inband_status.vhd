library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_logic, nsl_data, nsl_clocking;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use work.link_monitor.all;
use work.link.all;
use work.flit.all;

entity link_monitor_inband_status is
  generic(
    debounce_count_c : integer := 4
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    link_status_o: out link_status_t;

    rx_clock_i : in std_ulogic;
    rx_flit_i : in mii_flit_t
    );
end entity;

architecture beh of link_monitor_inband_status is

  type regs_t is
  record
    stable_count: integer range 0 to debounce_count_c - 1;
    last_ibs: std_ulogic_vector(3 downto 0);
  end record;

  signal ibs_s: std_ulogic_vector(3 downto 0);
  signal ibs_valid_s, ibs_stable_s: std_ulogic;

  signal r, rin: regs_t;

begin

  rx_regs: process(rx_clock_i) is
  begin
    if rising_edge(rx_clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.stable_count <= debounce_count_c-1;
      r.last_ibs <= x"0";
    end if;
  end process;

  rx_transition: process(r, rx_flit_i) is
  begin
    rin <= r;

    if rx_flit_i.error = '0' and rx_flit_i.valid = '0' then
      if r.last_ibs /= rx_flit_i.data(3 downto 0) then
        rin.stable_count <= debounce_count_c - 1;
        rin.last_ibs <= rx_flit_i.data(3 downto 0);
      elsif r.stable_count /= 0 then
        rin.stable_count <= r.stable_count - 1;
      end if;
    end if;
  end process;

  ibs_stable_s <= to_logic(r.stable_count = 0);
  
  interdomain: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => 4
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => rx_clock_i,
      clock_i(1) => clock_i,

      out_data_o => ibs_s,
      out_valid_o => ibs_valid_s,
      out_ready_i => '1',

      in_data_i => r.last_ibs,
      in_valid_i => ibs_stable_s
      );

  outputs: process(clock_i) is
  begin
    if rising_edge(clock_i) and ibs_valid_s = '1' then
      link_status_o <= rgmii_ibs_decode(ibs_s);
    end if;
  end process;

end architecture;
