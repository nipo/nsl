library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_clocking;

entity dapbus_m_o_sync is
  port(
    clock_i : in std_ulogic;

    dapbus_i : in nsl_coresight.dapbus.dapbus_m_o;
    dapbus_o : out nsl_coresight.dapbus.dapbus_m_o
    );
end entity;

architecture beh of dapbus_m_o_sync is

  signal stable, enable_in, enable_out : std_ulogic;

begin

  data_sync: nsl_clocking.async.async_stabilizer
    generic map(
      stable_count_c => 1,
      cycle_count_c => 2,
      data_width_c => 1 + 1 + 14 + 32 + 1 + 1
      )
    port map(
      clock_i => clock_i,
      data_i(0) => dapbus_i.sel,
      data_i(1) => dapbus_i.write,
      data_i(15 downto 2) => dapbus_i.addr,
      data_i(47 downto 16) => dapbus_i.wdata,
      data_i(48) => dapbus_i.abort,
      data_i(49) => enable_in,
      data_o(0) => dapbus_o.sel,
      data_o(1) => dapbus_o.write,
      data_o(15 downto 2) => dapbus_o.addr,
      data_o(47 downto 16) => dapbus_o.wdata,
      data_o(48) => dapbus_o.abort,
      data_o(49) => enable_out,
      stable_o => stable
      );

  dapbus_o.enable <= stable and enable_out;
  enable_in <= dapbus_i.sel and dapbus_i.enable;

end architecture;
