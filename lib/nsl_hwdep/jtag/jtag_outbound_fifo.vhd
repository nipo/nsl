library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking;

entity jtag_outbound_fifo is
  generic(
    id_c    : natural
    );
  port(
    clock_i        : in  std_ulogic;
    reset_n_i      : in  std_ulogic;
    jtag_reset_n_o : out std_ulogic;

    data_i  : in  std_ulogic_vector;
    valid_i : in  std_ulogic;
    last_i  : in  std_ulogic;
    ready_o : out std_ulogic
    );
end entity;

architecture beh of jtag_outbound_fifo is

  signal jtag_data : std_ulogic_vector(data_i'length + 1 downto 0);
  signal jtag_capture : std_ulogic;
  signal jtag_reset_n, reset_n, jtag_clock : std_ulogic;
  
begin

  reset_n <= jtag_reset_n and reset_n_i;
  jtag_reset_n_o <= jtag_reset_n;

  reg : nsl_hwdep.jtag.jtag_reg
    generic map(
      width_c => jtag_data'length,
      id_c => id_c
      )
    port map(
      clock_o => jtag_clock,
      reset_n_o => jtag_reset_n,

      data_i => jtag_data,
      capture_o => jtag_capture
      );

  resync: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => jtag_data'length - 1
      )
    port map(
      reset_n_i => reset_n,
      clock_i(0) => clock_i,
      clock_i(1) => jtag_clock,

      in_data_i(data_i'range) => data_i,
      in_data_i(data_i'length) => last_i,
      in_valid_i => valid_i,
      in_ready_o => ready_o,

      out_data_o => jtag_data(jtag_data'length-2 downto 0),
      out_valid_o => jtag_data(jtag_data'length-1),
      out_ready_i => jtag_capture
      );

end architecture;
