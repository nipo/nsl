library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_memory;
use nsl_memory.rom.rom_implementation_t;

entity rom_bytes_2p is
  generic (
    implementation_c : rom_implementation_t := ROM_BLOCK;
    word_addr_size_c : natural;
    word_byte_count_c : natural;
    -- word_byte_count_c * 2 ** word_addr_size_c bytes
    contents_c : nsl_data.bytestream.byte_string;
    little_endian_c : boolean := true
    );
  port (
    clock_i : in std_ulogic;

    a_read_i : in std_ulogic := '1';
    a_address_i : in unsigned(word_addr_size_c-1 downto 0);
    a_data_o : out std_ulogic_vector(8*word_byte_count_c-1 downto 0);

    b_read_i : in std_ulogic := '1';
    b_address_i : in unsigned(word_addr_size_c-1 downto 0);
    b_data_o : out std_ulogic_vector(8*word_byte_count_c-1 downto 0)
    );
begin

  assert
    contents_c'length = word_byte_count_c * 2 ** word_addr_size_c
    report "Initialization vector does not match ROM size"
    severity failure;

end entity;

architecture beh of rom_bytes_2p is

  subtype word_t is unsigned(word_byte_count_c * 8 - 1 downto 0);
  type mem_t is array(natural range 0 to 2**word_addr_size_c-1) of word_t;
  
  function ram_init(blob : nsl_data.bytestream.byte_string) return mem_t is
    alias xblob: nsl_data.bytestream.byte_string(0 to blob'length-1) is blob;
    variable ret : mem_t := (others => (others => '0'));
    variable tmp : nsl_data.bytestream.byte_string(0 to word_byte_count_c-1);
  begin
    for i in 0 to (blob'length / word_byte_count_c) - 1
    loop
      tmp := xblob(i*word_byte_count_c to (i+1) * word_byte_count_c - 1);
      if little_endian_c then
        ret(i) := nsl_data.endian.from_le(tmp);
      else
        ret(i) := nsl_data.endian.from_be(tmp);
      end if;
    end loop;

    return ret;
  end function;

  constant memory : mem_t := ram_init(contents_c);

  function to_rom_style(i: rom_implementation_t) return string
    is
  begin
    if i = ROM_BLOCK then
      return "block";
    elsif i = ROM_DISTRIBUTED then
      return "distributed";
    else
      return "distributed";
    end if;
  end function;

  function to_syn_romstyle(i: rom_implementation_t) return string
    is
  begin
    if i = ROM_BLOCK then
      return "block_rom";
    elsif i = ROM_DISTRIBUTED then
      return "distributed_rom";
    else
      return "logic";
    end if;
  end function;

  -- Xilinx attaches rom_style to the storage array
  attribute rom_style : string;
  attribute rom_style of memory : constant is to_rom_style(implementation_c);
  -- Gowin attaches syn_romstyle to the output signal
  attribute syn_romstyle : string;
  attribute syn_romstyle of a_data_o : signal is to_syn_romstyle(implementation_c);
  attribute syn_romstyle of b_data_o : signal is to_syn_romstyle(implementation_c);

begin

  reader: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      if a_read_i = '1' then
        a_data_o <= std_ulogic_vector(memory(to_integer(a_address_i)));
      end if;

      if b_read_i = '1' then
        b_data_o <= std_ulogic_vector(memory(to_integer(b_address_i)));
      end if;
    end if;
  end process;
  
end architecture;
