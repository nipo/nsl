library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
use hwdep.jtag.jtag_reg;

entity jtag_outbound_fifo is
  generic(
    width : natural;
    id    : natural
    );
  port(
    p_clk       : out std_ulogic;
    p_resetn    : out std_ulogic;

    p_data  : in std_ulogic_vector(width-1 downto 0);
    p_ack   : out std_ulogic
    );
end entity;

architecture beh of jtag_outbound_fifo is

  signal s_clk, s_shift, s_capture, s_reset, s_selected: std_ulogic;

  type regs_t is record
    reg: std_ulogic_vector(width-1 downto 0);
    bit_counter: natural range 0 to width-1;
  end record;

  signal r, rin: regs_t;

begin

  tap : hwdep.jtag.jtag_tap_register
    generic map(
      id => id
      )
    port map(
      p_tck      => s_clk,
      p_reset    => s_reset,
      p_selected => s_selected,
      p_capture  => s_capture,
      p_shift    => s_shift,
      p_update   => open,
      p_tdi      => open,
      p_tdo      => rin.reg(0)
      );

  p_resetn <= not s_reset;
  p_clk <= s_clk;
  p_ack <= '1' when r.bit_counter = width - 1 and s_shift = '1' and s_selected = '1' else '0';

  regs: process(s_clk)
  begin
    if rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_data, r, s_capture, s_selected, s_shift)
  begin
    rin <= r;

    if s_capture = '1' or s_selected = '0' then
      rin.bit_counter <= width - 1;
    elsif s_shift = '1' then
      if r.bit_counter = width - 1 then
        rin.reg <= p_data;
      else
        rin.reg <= '-' & r.reg(width-1 downto 1);
      end if;
      rin.bit_counter <= r.bit_counter - 1;
      if r.bit_counter = 0 then
        rin.bit_counter <= width - 1;
      end if;
    end if;
  end process;

end architecture;
