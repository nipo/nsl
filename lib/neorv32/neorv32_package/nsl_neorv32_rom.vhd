library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_memory, nsl_data, nsl_synthesis, nsl_math;
use neorv32.neorv32_package.all;
use neorv32.nsl_adaptation.all;

entity nsl_neorv32_rom is
  generic (
    init_file_name_c : string;
    byte_count_c    : natural := 0
  );
  port (
    clk_i     : in  std_ulogic; -- global clock line
    rstn_i    : in  std_ulogic; -- async reset, low-active
    bus_req_i : in  bus_req_t;  -- bus request
    bus_rsp_o : out bus_rsp_t   -- bus response
  );
end nsl_neorv32_rom;

architecture rtl of nsl_neorv32_rom is

  constant init_data_c: nsl_data.bytestream.byte_string := nsl_data.binary_io.file_load(init_file_name_c);
  constant rom_size_c: integer:= nsl_math.arith.max(init_data_c'length, byte_count_c);
  signal ben: std_ulogic_vector(3 downto 0);
  signal ren: std_ulogic;
  signal rdata: std_ulogic_vector(31 downto 0);

begin

  log0: nsl_synthesis.logging.synth_log
    generic map(
      message_c => "Loaded " & natural'image(init_data_c'length) & " bytes from " & init_file_name_c
      )
    port map(
      unused_i => '0'
      );

  log1: nsl_synthesis.logging.synth_log
    generic map(
      message_c => "[NEORV32] Implementing DEFAULT processor-internal IMEM as pre-initialized ROM."
      )
    port map(
      unused_i => '0'
      );

  rom: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => index_size_f(rom_size_c/4),
      word_byte_count_c => 4,
      contents_c => init_data_c,
      little_endian_c => true
      )
    port map(
      clock_i => clk_i,
      read_i => '1',
      address_i => unsigned(bus_req_i.addr(index_size_f(rom_size_c/4)+1 downto 2)),
      data_o => rdata
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
