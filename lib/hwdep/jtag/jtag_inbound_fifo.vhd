library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
use hwdep.jtag.jtag_tap_register;

entity jtag_inbound_fifo is
  generic(
    width : natural;
    id    : natural;
    sync_word_width: natural
    );
  port(
    p_clk       : out std_ulogic;
    p_resetn    : out std_ulogic;
    sync_word : std_ulogic_vector(sync_word_width-1 downto 0);

    p_data  : out std_ulogic_vector(width-1 downto 0);
    p_val   : out std_ulogic
    );
end entity;

architecture beh of jtag_inbound_fifo is

  signal s_clk, s_shift, s_tdi, s_reset, s_capture, s_update, s_selected: std_ulogic;

  type regs_t is record
    reg: std_ulogic_vector(width-1 downto 0);
    sync_reg: std_ulogic_vector(sync_word'range);
    bit_counter: natural range 0 to width-1;
    synced: boolean;
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
      p_update   => s_update,
      p_tdi      => s_tdi,
      p_tdo      => r.reg(0)
      );

  p_resetn <= not s_reset;
  p_clk <= s_clk;
  p_data <= rin.reg;
  p_val <= '1' when r.bit_counter = 0 and s_shift = '1' and r.synced else '0';
  
  regs: process(s_reset, s_clk)
  begin
    if s_reset = '1' then
      r.synced <= false;
    elsif rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_capture, s_selected, s_shift, s_tdi, s_update,
                      sync_word)
    variable sval: std_ulogic_vector(sync_word'range);
  begin
    sval := s_tdi & r.sync_reg(sync_word'high downto sync_word'low + 1);
    rin <= r;
    
    if s_capture = '1' or s_update = '1' or s_selected = '0' then
      rin.sync_reg <= (others => '0');
      rin.synced <= false;
    elsif s_shift = '1' then
      if not r.synced then
        rin.sync_reg <= sval;
        if sval = sync_word then
          rin.synced <= true;
          rin.bit_counter <= width - 1;
        end if;
      else
        rin.reg <= s_tdi & r.reg(width-1 downto 1);
        rin.bit_counter <= r.bit_counter - 1;
        if r.bit_counter = 0 then
          rin.bit_counter <= width - 1;
        end if;
      end if;
    end if;
  end process;

end architecture;
