library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_memory, nsl_data, nsl_synthesis;
use neorv32.neorv32_package.all;
use neorv32.nsl_adaptation.all;

entity nsl_neorv32_ram is
  generic (
    byte_count_c    : natural
    );
  port (
    clk_i     : in  std_ulogic;
    rstn_i    : in  std_ulogic;
    bus_req_i : in  bus_req_t;
    bus_rsp_o : out bus_rsp_t
    );
end nsl_neorv32_ram;

architecture rtl of nsl_neorv32_ram is

  signal ben: std_ulogic_vector(3 downto 0);
  signal ren: std_ulogic;
  signal rdata: std_ulogic_vector(31 downto 0);

begin

  ben <= bus_req_i.ben when bus_req_i.rw = '1' else x"0";
  
  ram: nsl_memory.ram.ram_1p_multi
    generic map(
      addr_size_c => index_size_f(byte_count_c/4),
      word_size_c => 8,
      data_word_count_c => 4
      )
    port map(
      clock_i => clk_i,
      address_i => unsigned(bus_req_i.addr(index_size_f(byte_count_c/4)+1 downto 2)),
      enable_i => bus_req_i.stb,
      write_en_i => ben,
      write_data_i => bus_req_i.data,
      read_data_o => rdata
      );

  bus_feedback: process(rstn_i, clk_i)
  begin
    if rising_edge(clk_i) then
      bus_rsp_o.ack <= bus_req_i.stb;
      ren <= bus_req_i.stb and not bus_req_i.rw;
    end if;

    if rstn_i = '0' then
      bus_rsp_o.ack <= '0';
      ren <= '0';
    end if;
  end process bus_feedback;

  bus_rsp_o.data <= rdata when ren = '1' else (others => '0');
  bus_rsp_o.err <= '0';

end rtl;
