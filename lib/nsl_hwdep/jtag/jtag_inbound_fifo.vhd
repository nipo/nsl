library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_math, nsl_clocking;

entity jtag_inbound_fifo is
  generic(
    id_c    : natural
    );
  port(
    clock_i        : in std_ulogic;
    reset_n_i      : in std_ulogic;
    jtag_reset_n_o : out std_ulogic;

    data_o  : out std_ulogic_vector;
    last_o  : out std_ulogic;
    valid_o : out std_ulogic;
    ready_i : in  std_ulogic
    );
end entity;

architecture beh of jtag_inbound_fifo is

  signal jtag_din, jtag_dout, jtag_resynced : std_ulogic_vector(data_o'length downto 0);
  signal jtag_update : std_ulogic;
  signal jtag_reset_n, reset_n, jtag_clock : std_ulogic;
  
begin

  reset_n <= jtag_reset_n and reset_n_i;
  jtag_reset_n_o <= jtag_reset_n;
  jtag_dout(jtag_dout'left downto 1) <= (others => '0');
  
  reg : nsl_hwdep.jtag.jtag_reg
    generic map(
      width_c => jtag_din'length,
      id_c => id_c
      )
    port map(
      clock_o => jtag_clock,
      reset_n_o => jtag_reset_n,

      data_o => jtag_din,
      update_o => jtag_update,

      data_i => jtag_dout,
      capture_o => open
      );

  data_o <= jtag_resynced(data_o'length-1 downto 0);
  last_o <= jtag_resynced(data_o'length);

  resync: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => jtag_din'length
      )
    port map(
      reset_n_i => reset_n,
      clock_i(0) => jtag_clock,
      clock_i(1) => clock_i,

      out_data_o => jtag_resynced,
      out_ready_i => ready_i,
      out_valid_o => valid_o,

      in_data_i => jtag_din,
      in_valid_i => jtag_update,
      in_ready_o => jtag_dout(0)
      );

end architecture;
