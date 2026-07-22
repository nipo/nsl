library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.apb.all;
use nsl_data.bytestream.all;

entity tb is
end entity;

architecture sim of tb is

  constant cfg_c : config_t := config(address_width => 12,
                                      data_bus_width => 32,
                                      err => true);

  constant contents_c : byte_string(0 to 11) := (
    x"00", x"01", x"02", x"03",
    x"04", x"05", x"06", x"07",
    x"08", x"09", x"0a", x"0b");

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';
  signal done_s : boolean := false;
  signal m_s : master_t;
  signal s_s : slave_t;

begin

  dut: nsl_amba.rom.apb_rom
    generic map(
      config_c => cfg_c,
      contents_c => contents_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      apb_i => m_s,
      apb_o => s_s
      );

  clock_gen: process
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 5 ns;
      clock_s <= '1';
      wait for 5 ns;
    end loop;
    wait;
  end process;

  stim: process
  begin
    m_s <= transfer_idle(cfg_c);
    reset_n_s <= '0';
    wait for 23 ns;
    wait until falling_edge(clock_s);
    reset_n_s <= '1';
    wait until falling_edge(clock_s);

    -- Word reads: each word is the little-endian assembly of four
    -- contents bytes.
    apb_check(cfg_c, clock_s, s_s, m_s, addr => to_unsigned(0, 12), val => unsigned'(x"03020100"));
    apb_check(cfg_c, clock_s, s_s, m_s, addr => to_unsigned(4, 12), val => unsigned'(x"07060504"));
    apb_check(cfg_c, clock_s, s_s, m_s, addr => to_unsigned(8, 12), val => unsigned'(x"0b0a0908"));
    -- Zero-padded tail word (contents rounded up to a power-of-two word count).
    apb_check(cfg_c, clock_s, s_s, m_s, addr => to_unsigned(12, 12), val => unsigned'(x"00000000"));
    -- Writes are rejected with SLVERR.
    apb_write(cfg_c, clock_s, s_s, m_s, reg => 0, val => unsigned'(x"deadbeef"), err => true);

    report "apb_rom testbench PASSED" severity note;
    done_s <= true;
    wait;
  end process;

end architecture;
