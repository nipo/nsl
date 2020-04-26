library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory;

entity ram_2p is
  generic (
    a_addr_size_c : natural;
    a_data_byte_count_c : natural;

    b_addr_size_c : natural;
    b_data_byte_count_c : natural;

    registered_output_c : boolean := false
    );
  port (
    a_clock_i   : in  std_ulogic;
    a_enable_i    : in  std_ulogic                               := '1';
    a_address_i  : in  unsigned(a_addr_size_c-1 downto 0);
    a_write_en_i   : in  std_ulogic_vector (a_data_byte_count_c-1 downto 0) := (others => '1');
    a_data_i : in  std_ulogic_vector (a_data_byte_count_c*8-1 downto 0) := (others => '-');
    a_data_o : out std_ulogic_vector (a_data_byte_count_c*8-1 downto 0);

    b_clock_i   : in  std_ulogic;
    b_enable_i    : in  std_ulogic                               := '1';
    b_address_i  : in  unsigned (b_addr_size_c-1 downto 0);
    b_write_en_i   : in  std_ulogic_vector (b_data_byte_count_c-1 downto 0) := (others => '1');
    b_data_i : in  std_ulogic_vector (b_data_byte_count_c*8-1 downto 0) := (others => '-');
    b_data_o : out std_ulogic_vector (b_data_byte_count_c*8-1 downto 0)
    );
begin

  assert 2**a_addr_size_c * a_data_byte_count_c = 2**b_addr_size_c * b_data_byte_count_c
    report "Both memory sizes are not equal"
    severity failure;

end ram_2p;

architecture inferred of ram_2p is

  constant max_word_bytes : natural := nsl_math.arith.max(a_data_byte_count_c, b_data_byte_count_c);
  constant min_addr_size_c : natural := nsl_math.arith.min(a_addr_size_c, b_addr_size_c);
  constant addr_size_c : natural := a_addr_size_c + nsl_math.arith.log2(a_data_byte_count_c);

  constant mem_size_c : natural := 2**min_addr_size_c;
  subtype word_t is std_ulogic_vector(max_word_bytes*8-1 downto 0);
  subtype en_t is std_ulogic_vector(max_word_bytes-1 downto 0);

  constant a_addr_lsb_bits : natural := a_addr_size_c - min_addr_size_c;
  constant b_addr_lsb_bits : natural := b_addr_size_c - min_addr_size_c;
  constant a_addr_lsb_wrap : natural := 2**a_addr_lsb_bits;
  constant b_addr_lsb_wrap : natural := 2**b_addr_lsb_bits;
  signal a_addr_lsb, a_addr_lsb_reg : natural range 0 to a_addr_lsb_wrap-1;
  signal b_addr_lsb, b_addr_lsb_reg : natural range 0 to b_addr_lsb_wrap-1;

  signal a_rdata, a_wdata, b_rdata, b_wdata : word_t;
  signal a_wen, b_wen : en_t;

begin

  ram: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => min_addr_size_c,
      word_size_c => 8,
      data_word_count_c => max_word_bytes,
      registered_output_c => registered_output_c
      )
    port map(
      a_clock_i   => a_clock_i,
      a_address_i  => a_address_i(a_addr_size_c-1 downto a_addr_size_c-min_addr_size_c),
      a_enable_i    => a_enable_i,
      a_data_i => a_wdata,
      a_write_en_i   => a_wen,
      a_data_o => a_rdata,

      b_clock_i   => b_clock_i,
      b_address_i  => b_address_i(b_addr_size_c-1 downto b_addr_size_c-min_addr_size_c),
      b_enable_i    => b_enable_i,
      b_data_i => b_wdata,
      b_write_en_i   => b_wen,
      b_data_o => b_rdata
      );

  a_wdata_gen: process(a_data_i)
    variable i : natural;
  begin
    for i in 0 to a_addr_lsb_wrap-1
    loop
      a_wdata((i+1)*a_data_byte_count_c*8-1 downto i*a_data_byte_count_c*8)
        <= a_data_i;
      end loop;
  end process;

  a_wen_gen: process(a_address_i, a_write_en_i)
    variable lsb : natural range 0 to a_addr_lsb_wrap-1;
    variable i : natural;
  begin
    lsb := to_integer(to_01(a_address_i(a_addr_size_c-min_addr_size_c-1 downto 0), '0'));
    a_wen <= (others => '0');

    for i in 0 to a_data_byte_count_c-1
    loop
      a_wen(lsb*a_data_byte_count_c+i) <= a_write_en_i(i);
    end loop;
  end process;

  a_rdata_off: process(a_clock_i)
  begin
    if rising_edge(a_clock_i) then
      if a_enable_i = '1' then
        if registered_output_c then
          a_addr_lsb_reg <= to_integer(to_01(a_address_i(a_addr_size_c-min_addr_size_c-1 downto 0), '0'));
          a_addr_lsb <= a_addr_lsb_reg;
        else
          a_addr_lsb <= to_integer(to_01(a_address_i(a_addr_size_c-min_addr_size_c-1 downto 0), '0'));
        end if;
      end if;
    end if;
  end process;

  b_wdata_gen: process(b_data_i)
    variable i : natural;
  begin
    for i in 0 to b_addr_lsb_wrap-1
    loop
      b_wdata((i+1)*b_data_byte_count_c*8-1 downto i*b_data_byte_count_c*8)
        <= b_data_i;
    end loop;
  end process;

  b_wen_gen: process(b_address_i, b_write_en_i)
    variable lsb : natural range 0 to b_addr_lsb_wrap-1;
  begin
    lsb := to_integer(to_01(b_address_i(b_addr_size_c-min_addr_size_c-1 downto 0), '0'));
    b_wen <= (others => '0');

    for i in 0 to b_data_byte_count_c-1
    loop
      b_wen(lsb*b_data_byte_count_c+i) <= b_write_en_i(i);
    end loop;
  end process;

  b_rdata_off: process (b_clock_i)
  begin
    if rising_edge(b_clock_i) then
      if b_enable_i = '1' then
        if registered_output_c then
          b_addr_lsb_reg <= to_integer(to_01(b_address_i(b_addr_size_c-min_addr_size_c-1 downto 0), '0'));
          b_addr_lsb <= b_addr_lsb_reg;
        else
          b_addr_lsb <= to_integer(to_01(b_address_i(b_addr_size_c-min_addr_size_c-1 downto 0), '0'));
        end if;
      end if;
    end if;
  end process;

  a_data_o <= a_rdata((a_addr_lsb*a_data_byte_count_c+a_data_byte_count_c)*8-1 downto a_addr_lsb*a_data_byte_count_c*8);
  b_data_o <= b_rdata((b_addr_lsb*b_data_byte_count_c+b_data_byte_count_c)*8-1 downto b_addr_lsb*b_data_byte_count_c*8);

end inferred;
