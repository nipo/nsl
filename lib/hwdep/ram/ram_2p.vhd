library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, hwdep;

entity ram_2p is
  generic (
    a_addr_size : natural;
    a_data_byte_count : natural;

    b_addr_size : natural;
    b_data_byte_count : natural;

    registered_output : boolean := false
    );
  port (
    p_a_clk   : in  std_ulogic;
    p_a_en    : in  std_ulogic                               := '1';
    p_a_addr  : in  std_ulogic_vector (a_addr_size-1 downto 0);
    p_a_wen   : in  std_ulogic_vector (a_data_byte_count-1 downto 0) := (others => '1');
    p_a_wdata : in  std_ulogic_vector (a_data_byte_count*8-1 downto 0) := (others => '-');
    p_a_rdata : out std_ulogic_vector (a_data_byte_count*8-1 downto 0);

    p_b_clk   : in  std_ulogic;
    p_b_en    : in  std_ulogic                               := '1';
    p_b_addr  : in  std_ulogic_vector (b_addr_size-1 downto 0);
    p_b_wen   : in  std_ulogic_vector (b_data_byte_count-1 downto 0) := (others => '1');
    p_b_wdata : in  std_ulogic_vector (b_data_byte_count*8-1 downto 0) := (others => '-');
    p_b_rdata : out std_ulogic_vector (b_data_byte_count*8-1 downto 0)
    );
begin

  assert 2**a_addr_size * a_data_byte_count = 2**b_addr_size * b_data_byte_count
    report "Both memory sizes are not equal"
    severity failure;

end ram_2p;

architecture inferred of ram_2p is

  function max(x, y : natural) return natural is
  begin
    if x < y then
      return y;
    else
      return x;
    end if;
  end max;

  function min(x, y : natural) return natural is
  begin
    if x < y then
      return x;
    else
      return y;
    end if;
  end min;

  constant max_word_bytes : natural := max(a_data_byte_count, b_data_byte_count);
  constant min_addr_size : natural := min(a_addr_size, b_addr_size);
  constant addr_size : natural := a_addr_size + util.numeric.log2(a_data_byte_count);

  constant mem_size : natural := 2**min_addr_size;
  subtype word_t is std_ulogic_vector(max_word_bytes*8-1 downto 0);
  subtype en_t is std_ulogic_vector(max_word_bytes-1 downto 0);

  constant a_addr_lsb_bits : natural := a_addr_size - min_addr_size;
  constant b_addr_lsb_bits : natural := b_addr_size - min_addr_size;
  constant a_addr_lsb_wrap : natural := 2**a_addr_lsb_bits;
  constant b_addr_lsb_wrap : natural := 2**b_addr_lsb_bits;
  signal a_addr_lsb, a_addr_lsb_reg : natural range 0 to a_addr_lsb_wrap-1;
  signal b_addr_lsb, b_addr_lsb_reg : natural range 0 to b_addr_lsb_wrap-1;

  signal a_rdata, a_wdata, b_rdata, b_wdata : word_t;
  signal a_wen, b_wen : en_t;

begin

  ram: hwdep.ram.ram_2p_homogeneous
    generic map(
      addr_size => min_addr_size,
      word_size => 8,
      data_word_count => max_word_bytes,
      registered_output => registered_output
      )
    port map(
      p_a_clk   => p_a_clk,
      p_a_addr  => p_a_addr(a_addr_size-1 downto a_addr_size-min_addr_size),
      p_a_en    => p_a_en,
      p_a_wdata => a_wdata,
      p_a_wen   => a_wen,
      p_a_rdata => a_rdata,

      p_b_clk   => p_b_clk,
      p_b_addr  => p_b_addr(b_addr_size-1 downto b_addr_size-min_addr_size),
      p_b_en    => p_b_en,
      p_b_wdata => b_wdata,
      p_b_wen   => b_wen,
      p_b_rdata => b_rdata
      );

  a_wdata_gen: process(p_a_wdata)
    variable i : natural;
  begin
    for i in 0 to a_addr_lsb_wrap-1
    loop
      a_wdata((i+1)*a_data_byte_count*8-1 downto i*a_data_byte_count*8)
        <= p_a_wdata;
      end loop;
  end process;

  a_wen_gen: process(p_a_addr, p_a_wen)
    variable lsb : natural range 0 to a_addr_lsb_wrap-1;
    variable i : natural;
  begin
    lsb := to_integer(to_01(unsigned(p_a_addr(a_addr_size-min_addr_size-1 downto 0)), '0'));
    a_wen <= (others => '0');

    for i in 0 to a_data_byte_count-1
    loop
      a_wen(lsb*a_data_byte_count+i) <= p_a_wen(i);
    end loop;
  end process;

  a_rdata_off: process(p_a_clk)
  begin
    if rising_edge(p_a_clk) then
      if p_a_en = '1' then
        if registered_output then
          a_addr_lsb_reg <= to_integer(to_01(unsigned(p_a_addr(a_addr_size-min_addr_size-1 downto 0)), '0'));
          a_addr_lsb <= a_addr_lsb_reg;
        else
          a_addr_lsb <= to_integer(to_01(unsigned(p_a_addr(a_addr_size-min_addr_size-1 downto 0)), '0'));
        end if;
      end if;
    end if;
  end process;

  b_wdata_gen: process(p_b_wdata)
    variable i : natural;
  begin
    for i in 0 to b_addr_lsb_wrap-1
    loop
      b_wdata((i+1)*b_data_byte_count*8-1 downto i*b_data_byte_count*8)
        <= p_b_wdata;
    end loop;
  end process;

  b_wen_gen: process(p_b_addr, p_b_wen)
    variable lsb : natural range 0 to b_addr_lsb_wrap-1;
  begin
    lsb := to_integer(to_01(unsigned(p_b_addr(b_addr_size-min_addr_size-1 downto 0)), '0'));
    b_wen <= (others => '0');

    for i in 0 to b_data_byte_count-1
    loop
      b_wen(lsb*b_data_byte_count+i) <= p_b_wen(i);
    end loop;
  end process;

  b_rdata_off: process (p_b_clk)
  begin
    if rising_edge(p_b_clk) then
      if p_b_en = '1' then
        if registered_output then
          b_addr_lsb_reg <= to_integer(to_01(unsigned(p_b_addr(b_addr_size-min_addr_size-1 downto 0)), '0'));
          b_addr_lsb <= b_addr_lsb_reg;
        else
          b_addr_lsb <= to_integer(to_01(unsigned(p_b_addr(b_addr_size-min_addr_size-1 downto 0)), '0'));
        end if;
      end if;
    end if;
  end process;

  p_a_rdata <= a_rdata((a_addr_lsb+a_data_byte_count)*8-1 downto a_addr_lsb*8);
  p_b_rdata <= b_rdata((b_addr_lsb+b_data_byte_count)*8-1 downto b_addr_lsb*8);

end inferred;
