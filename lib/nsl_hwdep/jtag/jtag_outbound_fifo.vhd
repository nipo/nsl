library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep;

entity jtag_outbound_fifo is
  generic(
    id_c    : natural
    );
  port(
    clock_o       : out std_ulogic;
    reset_n_o    : out std_ulogic;

    data_o  : in std_ulogic_vector;
    ready_o   : out std_ulogic
    );
end entity;

architecture beh of jtag_outbound_fifo is

  signal s_clk, s_shift, s_capture, s_reset, s_selected: std_ulogic;

  type regs_t is record
    reg: std_ulogic_vector(data_o'length-1 downto 0);
    bit_counter: natural range 0 to data_o'length-1;
  end record;

  signal r, rin: regs_t;

begin

  tap : nsl_hwdep.jtag.jtag_tap_register
    generic map(
      id_c => id_c
      )
    port map(
      tck_o      => s_clk,
      reset_o    => s_reset,
      selected_o => s_selected,
      capture_o  => s_capture,
      shift_o    => s_shift,
      update_o   => open,
      tdi_o      => open,
      tdo_i      => rin.reg(0)
      );

  reset_n_o <= not s_reset;
  clock_o <= s_clk;
  ready_o <= '1' when r.bit_counter = data_o'length - 1 and s_shift = '1' and s_selected = '1' else '0';

  regs: process(s_clk)
  begin
    if rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(data_o, r, s_capture, s_selected, s_shift)
  begin
    rin <= r;

    if s_capture = '1' or s_selected = '0' then
      rin.bit_counter <= data_o'length - 1;
    elsif s_shift = '1' then
      if r.bit_counter = data_o'length - 1 then
        rin.reg <= data_o;
      else
        rin.reg <= '-' & r.reg(data_o'length-1 downto 1);
      end if;
      if r.bit_counter = 0 then
        rin.bit_counter <= data_o'length - 1;
      else
        rin.bit_counter <= r.bit_counter - 1;
      end if;
    end if;
  end process;

end architecture;
