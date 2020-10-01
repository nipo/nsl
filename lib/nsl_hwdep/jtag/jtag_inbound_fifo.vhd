library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep;

entity jtag_inbound_fifo is
  generic(
    id_c    : natural
    );
  port(
    clock_o    : out std_ulogic;
    reset_n_o  : out std_ulogic;
    sync_i     : in std_ulogic_vector;

    data_o     : out std_ulogic_vector;
    valid_o    : out std_ulogic
    );
end entity;

architecture beh of jtag_inbound_fifo is

  signal s_clk, s_shift, s_tdi, s_reset, s_capture, s_update, s_selected: std_ulogic;

  constant max_width : natural := nsl_math.arith.max(data_o'length, sync_i'length)
  
  type regs_t is record
    reg: std_ulogic_vector(max_width-1 downto 0);
    bit_counter: natural range 0 to data_o'length-1;
    synced: boolean;
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
      update_o   => s_update,
      tdi_o      => s_tdi,
      tdo_i      => r.reg(0)
      );

  reset_n_o <= not s_reset;
  clock_o <= s_clk;
  data_o <= rin.reg(data_o'length-1 downto 0);
  valid_o <= '1' when r.bit_counter = 0 and s_shift = '1' and r.synced else '0';
  
  regs: process(s_reset, s_clk)
  begin
    if s_reset = '1' then
      r.synced <= false;
    elsif rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, s_capture, s_selected, s_shift, s_tdi, s_update,
                      sync_i)
  begin
    rin <= r;
    
    if s_capture = '1' or s_update = '1' or s_selected = '0' then
      rin.reg <= (others => '0');
      rin.synced <= false;
    elsif s_shift = '1' then
      rin.reg <= s_tdi & r.reg(r.reg'left downto 1);

      if not r.synced then
        if r.reg = sync_i then
          rin.synced <= true;
          rin.bit_counter <= data_o'length - 2;
        end if;
      else
        if r.bit_counter = 0 then
          rin.bit_counter <= data_o'length - 1;
        else
          rin.bit_counter <= r.bit_counter - 1;
        end if;
      end if;
    end if;
  end process;

end architecture;
