library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_data.endian.all;

entity wishbone_ram is
  generic(
    wb_config_c : wb_config_t;
    byte_size_l2_c : natural
    );
  port(
    clock_i : std_ulogic;
    reset_n_i : std_ulogic;

    wb_i : in wb_req_t;
    wb_o : out wb_ack_t
    );
end entity;

architecture beh of wishbone_ram is

  type regs_t is
  record
    was_accessed: boolean;
  end record;

  signal r, rin: regs_t;

  constant word_size_c : natural := 2**wb_config_c.port_granularity_l2;
  constant word_count_c : natural := wb_sel_width(wb_config_c);

  signal ram_address_s : unsigned(byte_size_l2_c-1 downto wb_address_lsb(wb_config_c));
  signal sel_s, ram_wen_s : std_ulogic_vector(wb_sel_width(wb_config_c)-1 downto 0);
  signal ram_wdata_s, ram_rdata_s: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
  signal ram_enable_s : std_ulogic;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.was_accessed <= false;
    end if;
  end process;

  transition: process(r, wb_i) is
  begin
    rin <= r;

    rin.was_accessed <= wbc_is_active(wb_config_c, wb_i);
  end process;

  outputs: process(r, ram_rdata_s) is
    variable rdata: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
    variable term: wb_term_t;
  begin
    rdata := (others => '-');
    term := WB_TERM_NONE;

    if r.was_accessed then
      term := WB_TERM_ACK;
      rdata := ram_rdata_s;

      if wb_config_c.endian = WB_ENDIAN_BIG then
        rdata := wbc_dat_endian_swap(wb_config_c, rdata);
      end if;
    end if;

    wb_o <= wbc_ack(wb_config_c,
                    term => term,
                    data => rdata);
  end process;      
  
  ram_control: process(wb_i) is
  begin
    if wb_config_c.endian = WB_ENDIAN_LITTLE then
      sel_s <= wbc_sel(wb_config_c, wb_i);
      ram_wdata_s <= wbc_data(wb_config_c, wb_i);
    else      
      sel_s <= wbc_sel_endian_swap(wb_config_c, wbc_sel(wb_config_c, wb_i));
      ram_wdata_s <= wbc_dat_endian_swap(wb_config_c, wbc_data(wb_config_c, wb_i));
    end if;

    if wbc_is_active(wb_config_c, wb_i) then
      ram_enable_s <= '1';
    else
      ram_enable_s <= '0';
    end if;
    ram_address_s <= wbc_address(wb_config_c, wb_i)(ram_address_s'range);
    if wbc_is_write(wb_config_c, wb_i) then
      ram_wen_s <= sel_s;
    else
      ram_wen_s <= (others => '0');
    end if;
  end process;

  memory: nsl_memory.ram.ram_1p_multi
    generic map(
      addr_size_c => ram_address_s'length,
      word_size_c => word_size_c,
      data_word_count_c => word_count_c
      )
    port map(
      clock_i => clock_i,

      address_i => ram_address_s,
      enable_i => ram_enable_s,
      write_en_i => ram_wen_s,
      write_data_i => ram_wdata_s,
      read_data_o => ram_rdata_s
      );
  
end architecture;
