library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, hwdep;

entity axi4_lite_a32_d32_ram is
  generic (
    mem_size_log2_c: natural := 12
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';
    
    axi_i: in nsl_axi.axi4_lite.a32_d32_ms;
    axi_o: out nsl_axi.axi4_lite.a32_d32_sm
    );
end entity;

architecture rtl of axi4_lite_a32_d32_ram is

  signal s_axi_write, s_axi_read, s_axi_read_done, s_axi_enable : std_ulogic;
  signal s_axi_wmask, s_axi_mem_wmask : std_ulogic_vector(3 downto 0);
  signal s_axi_addr : std_ulogic_vector(mem_size_log2_c-1 downto 2);
  signal s_axi_wdata, s_axi_rdata : std_ulogic_vector(31 downto 0);

begin

  axi_slave: nsl_axi.axi4_lite.axi4_lite_a32_d32_slave
    generic map(
      addr_size => mem_size_log2_c
      )
    port map(
      aclk => clock_i,
      aresetn => reset_n_i,

      p_axi_ms => axi_i,
      p_axi_sm => axi_o,

      p_addr => s_axi_addr,

      p_w_data => s_axi_wdata,
      p_w_mask => s_axi_wmask,
      p_w_ready => '1',
      p_w_valid => s_axi_write,

      p_r_data => s_axi_rdata,
      p_r_ready => s_axi_read,
      p_r_valid => s_axi_read_done
      );

  ram: hwdep.ram.ram_1p
    generic map(
      addr_size => mem_size_log2_c-2,
      data_size => 32
      )
    port map(
      p_clk => clock_i,
      p_addr => s_axi_addr,
      p_wen   => s_axi_mem_wmask(0),
      p_wdata  => s_axi_wdata,
      p_rdata => s_axi_rdata
      );

  s_axi_mem_wmask <= s_axi_wmask when s_axi_write = '1' else (others => '0');
  s_axi_enable <= s_axi_read or s_axi_write;

  read_done: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      s_axi_read_done <= '0';
    elsif rising_edge(clock_i) then
      s_axi_read_done <= s_axi_read;
    end if;
  end process;

end architecture;
