library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_clocking;

entity dapbus_m_i_sync is
  port(
    clock_i : in std_ulogic;

    dapbus_i : in nsl_coresight.dapbus.dapbus_m_i;
    dapbus_o : out nsl_coresight.dapbus.dapbus_m_i
    );
end entity;

architecture beh of dapbus_m_i_sync is

  signal stable, ready : std_ulogic;

begin

  data_sync: nsl_clocking.async.async_stabilizer
    generic map(
      stable_count_c => 1,
      cycle_count_c => 2,
      data_width_c => 32 + 1 + 1
      )
    port map(
      clock_i => clock_i,
      data_i(31 downto 0) => dapbus_i.rdata,
      data_i(32) => dapbus_i.slverr,
      data_i(33) => dapbus_i.ready,
      data_o(31 downto 0) => dapbus_o.rdata,
      data_o(32) => dapbus_o.slverr,
      data_o(33) => ready,
      stable_o => stable
      );

  dapbus_o.ready <= stable and ready;
  
end architecture;
