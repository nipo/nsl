library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lut_sync_2p is
  generic (
    input_width_c : natural;
    output_width_c : natural;
    -- output_width_c * 2 ** input_width_c bits
    contents_c : std_ulogic_vector
    );
  port (
    clock_i : in std_ulogic;

    a_enable_i : in std_ulogic := '1';
    a_i : in std_ulogic_vector(input_width_c-1 downto 0);
    a_o : out std_ulogic_vector(output_width_c-1 downto 0);

    b_enable_i : in std_ulogic := '1';
    b_i : in std_ulogic_vector(input_width_c-1 downto 0);
    b_o : out std_ulogic_vector(output_width_c-1 downto 0)
    );
begin

  assert
    contents_c'length = output_width_c * 2 ** input_width_c
    report "Initialization vector does not match LUT size"
    severity failure;

end entity;

architecture beh of lut_sync_2p is

  subtype word_t is std_ulogic_vector(output_width_c - 1 downto 0);
  type mem_t is array(natural range 0 to 2**input_width_c-1) of word_t;

  function ram_init(blob : std_ulogic_vector) return mem_t is
    alias b : std_ulogic_vector(0 to output_width_c * 2 ** input_width_c - 1) is blob;
    variable ret : mem_t;
  begin
    for i in 0 to ret'length-1
    loop
      ret(i) := b(i * output_width_c to (i+1) * output_width_c - 1);
    end loop;

    return ret;
  end function;

  constant memory : mem_t := ram_init(contents_c);

begin

  reader: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      if a_enable_i = '1' then
        a_o <= std_ulogic_vector(memory(to_integer(unsigned(a_i))));
      end if;

      if b_enable_i = '1' then
        b_o <= std_ulogic_vector(memory(to_integer(unsigned(b_i))));
      end if;
    end if;
  end process;
  
end architecture;
