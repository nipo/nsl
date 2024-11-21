library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_data.endian.all;

entity wishbone_ram_controller is
  generic(
    wb_config_c : wb_config_t;
    ram_byte_size_l2_c : natural
    );
  port(
    clock_i : std_ulogic;
    reset_n_i : std_ulogic;

    enable_o : out std_ulogic;
    address_o : out unsigned(ram_byte_size_l2_c-1 downto wb_address_lsb(wb_config_c));

    write_enable_o : out std_ulogic_vector(wb_sel_width(wb_config_c)-1 downto 0);
    write_data_o : out std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
    read_data_i : in std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);

    wb_i : in wb_req_t;
    wb_o : out wb_ack_t
    );
end entity;

architecture beh of wishbone_ram_controller is

  type regs_t is
  record
    was_accessed: boolean;
  end record;

  signal r, rin: regs_t;

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
  
  outputs: process(r, read_data_i, wb_i) is
    variable rdata: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
  begin
    wb_o <= wbc_ack(wb_config_c, term => WB_TERM_NONE);

    if r.was_accessed then
      rdata := read_data_i;

      if wb_config_c.endian = WB_ENDIAN_BIG then
        rdata := wbc_dat_endian_swap(wb_config_c, rdata);
      end if;

      wb_o <= wbc_ack(wb_config_c, data => rdata, term => WB_TERM_ACK);
    elsif wb_config_c.bus_type = WB_CLASSIC_PIPELINED and wbc_is_read(wb_config_c, wb_i) then
      wb_o <= wbc_ack(wb_config_c, stall => true);
    end if;
  end process;      
  
  ram_control: process(wb_i) is
    variable sel : std_ulogic_vector(wb_sel_width(wb_config_c)-1 downto 0);
  begin
    enable_o <= '0';
    write_enable_o <= (others => '0');
    address_o <= wbc_address(wb_config_c, wb_i)(address_o'range);

    if wbc_is_active(wb_config_c, wb_i) then
      enable_o <= '1';
    end if;

    if wb_config_c.endian = WB_ENDIAN_LITTLE then
      sel := wbc_sel(wb_config_c, wb_i);
      write_data_o <= wbc_data(wb_config_c, wb_i);
    else      
      sel := wbc_sel_endian_swap(wb_config_c, wbc_sel(wb_config_c, wb_i));
      write_data_o <= wbc_dat_endian_swap(wb_config_c, wbc_data(wb_config_c, wb_i));
    end if;

    if wbc_is_write(wb_config_c, wb_i) then
      write_enable_o <= sel;
    end if;
  end process;

end architecture;
