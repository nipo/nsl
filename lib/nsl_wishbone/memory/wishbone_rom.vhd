library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity wishbone_rom is
  generic(
    wb_config_c : wb_config_t;
    contents_c : nsl_data.bytestream.byte_string
    );
  port(
    clock_i : std_ulogic;
    reset_n_i : std_ulogic;

    wb_i : in wb_req_t;
    wb_o : out wb_ack_t
    );
end entity;

architecture beh of wishbone_rom is

  type regs_t is
  record
    was_accessed: boolean;
    was_error: boolean;
  end record;

  signal r, rin: regs_t;

  constant rom_size_l2_c : natural := nsl_math.arith.log2(contents_c'length);
  constant padding_c : nsl_data.bytestream.byte_string(contents_c'length to 2**rom_size_l2_c-1) := (others => x"00");

  constant init_c : nsl_data.bytestream.byte_string := contents_c & padding_c;

  constant word_size_c : natural := 2**wb_config_c.port_granularity_l2;

  signal rom_address_s : unsigned(rom_size_l2_c-1 downto wb_address_lsb(wb_config_c));
  signal rom_rdata_s: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
  signal rom_enable_s: std_ulogic;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.was_accessed <= false;
      r.was_error <= false;
    end if;
  end process;

  transition: process(r, wb_i) is
  begin
    rin <= r;

    rin.was_accessed <= wbc_is_read(wb_config_c, wb_i) or wbc_is_write(wb_config_c, wb_i);
    rin.was_error <= wbc_is_write(wb_config_c, wb_i);
  end process;

  outputs: process(r, rom_rdata_s) is
    variable rdata: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
    variable term: wb_term_t;
  begin
    rdata := (others => '-');
    term := WB_TERM_NONE;

    if r.was_accessed then
      if not r.was_error then
        term := WB_TERM_ACK;
        rdata := rom_rdata_s;

        if wb_config_c.endian = WB_ENDIAN_BIG then
          rdata := wbc_dat_endian_swap(wb_config_c, rdata);
        end if;
      else
        term := WB_TERM_ERROR;
      end if;
    end if;

    wb_o <= wbc_ack(wb_config_c,
                    term => term,
                    data => rdata);
  end process;

  rom_enable_s <= '1' when wbc_is_read(wb_config_c, wb_i) else '0';
  rom_address_s <= wbc_address(wb_config_c, wb_i)(rom_address_s'range);

  memory: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => rom_address_s'length,
      word_byte_count_c => word_size_c / 8,
      contents_c => init_c,
      little_endian_c => true
      )
    port map(
      clock_i => clock_i,

      read_i => rom_enable_s,
      address_i => rom_address_s,
      data_o => rom_rdata_s
      );

end architecture;
