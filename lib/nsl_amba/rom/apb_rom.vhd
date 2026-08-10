library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_memory, nsl_math;
use nsl_amba.apb.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_memory.rom.rom_implementation_t;

entity apb_rom is
  generic (
    config_c : config_t;
    implementation_c : rom_implementation_t := ROM_BLOCK;
    contents_c : byte_string
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic := '1';

    apb_i : in master_t;
    apb_o : out slave_t
    );
end entity;

architecture rtl of apb_rom is

  constant word_byte_count_c : natural := 2**config_c.data_bus_width_l2;
  constant word_count_c : natural :=
    (contents_c'length + word_byte_count_c - 1) / word_byte_count_c;
  constant word_addr_size_c : natural :=
    nsl_math.arith.max(1, nsl_math.arith.log2(word_count_c));
  constant rom_size_c : natural := (2**word_addr_size_c) * word_byte_count_c;

  -- rom_bytes needs exactly word_byte_count_c * 2**word_addr_size_c
  -- bytes; zero-pad the tail of the user contents to that size.
  constant pad_c : byte_string(0 to rom_size_c - contents_c'length - 1) :=
    (others => (others => '0'));
  constant rom_contents_c : byte_string(0 to rom_size_c - 1) := contents_c & pad_c;

  signal apb_addr_s : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal rom_addr_s : unsigned(word_addr_size_c-1 downto 0);
  signal apb_read_s, apb_read_done_s : std_ulogic;
  signal rom_data_s : std_ulogic_vector(8*word_byte_count_c-1 downto 0);
  signal apb_rbytes_s : byte_string(0 to word_byte_count_c-1);

begin

  slave: nsl_amba.apb.apb_slave
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      address_o => apb_addr_s,

      -- Read-only: accept the write beat but signal SLVERR.
      w_data_o => open,
      w_mask_o => open,
      w_ready_i => '1',
      w_error_i => '1',
      w_valid_o => open,

      r_data_i => apb_rbytes_s,
      r_ready_o => apb_read_s,
      r_valid_i => apb_read_done_s
      );

  rom: nsl_memory.rom.rom_bytes
    generic map(
      implementation_c => implementation_c,
      word_addr_size_c => word_addr_size_c,
      word_byte_count_c => word_byte_count_c,
      contents_c => rom_contents_c,
      little_endian_c => true
      )
    port map(
      clock_i => clock_i,
      read_i => '1',
      address_i => rom_addr_s,
      data_o => rom_data_s
      );

  rom_addr_s <= resize(apb_addr_s, word_addr_size_c);
  apb_rbytes_s <= to_le(unsigned(rom_data_s));

  -- rom_bytes has a one-cycle registered read latency: the data is
  -- valid the cycle after apb_slave asserts r_ready_o (the access
  -- phase). Delay r_valid_i by one cycle to match.
  read_done: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if apb_read_s = '1' and apb_read_done_s = '0' then
        apb_read_done_s <= '1';
      elsif apb_read_done_s = '1' then
        apb_read_done_s <= '0';
      end if;
    end if;

    if reset_n_i = '0' then
      apb_read_done_s <= '0';
    end if;
  end process;

end architecture;
