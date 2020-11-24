library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ram is

  -- A single-port RAM with registered ouptut.
  component ram_1p
    generic (
      addr_size_c : natural;
      data_size_c : natural
      );
    port (
      clock_i : in std_ulogic;

      address_i : in unsigned(addr_size_c-1 downto 0);
      enable_i : in std_ulogic := '1';

      write_en_i : in std_ulogic;
      write_data_i : in std_ulogic_vector(data_size_c-1 downto 0);

      read_data_o : out std_ulogic_vector(data_size_c-1 downto 0)
      );
  end component;

  -- A single-port RAM with registered ouptut and multi-word write.
  -- Address is base address of data word group
  -- I.e. this memory stores 2**addr_size_c * data_word_count_c * word_size_c bits.
  component ram_1p_multi
    generic (
      addr_size_c : natural;
      word_size_c : natural := 8;
      data_word_count_c : integer := 4
      );
    port (
      clock_i : in std_ulogic;

      address_i : in unsigned(addr_size_c-1 downto 0);
      enable_i : in std_ulogic := '1';

      write_en_i : in std_ulogic_vector(data_word_count_c-1 downto 0);
      write_data_i : in std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0);

      read_data_o : out std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0)
      );
  end component;

  -- A dual-port RAM with optionally two clocks, one port read, one
  -- port write.
  --
  -- Read data appears on interface after rising clock edge.
  -- If read port is disabled, last data is kept on interface, even if read
  -- address changes.
  component ram_2p_r_w
    generic (
      addr_size_c : natural;
      data_size_c : natural;
      clock_count_c : natural range 1 to 2 := 1;
      registered_output_c : boolean := false
      );
    port (
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);

      write_address_i : in unsigned(addr_size_c-1 downto 0);
      write_en_i : in std_ulogic := '0';
      write_data_i : in std_ulogic_vector(data_size_c-1 downto 0) := (others => '-');

      read_address_i : in unsigned(addr_size_c-1 downto 0);
      read_en_i : in std_ulogic := '1';
      read_data_o : out std_ulogic_vector(data_size_c-1 downto 0)
      );
  end component;

  -- Size-homogeneous dual port RAM. Offers parallel read and write
  -- interface of multiple words (each word has an independant
  -- write-strobe signal).
  --
  -- When writing, both enable and write_en signals need to be
  -- asserted.
  --
  -- If registered output is enabled, there is a two rising clock edge
  -- latency between address and data output. If not enabled, there is
  -- only one.
  component ram_2p_homogeneous is
    generic(
      addr_size_c : integer := 10;
      word_size_c : integer := 8;
      data_word_count_c : integer := 4;
      registered_output_c : boolean := false;
      b_can_write_c : boolean := true
      );
    port(
      a_clock_i : in std_ulogic;
      a_enable_i : in std_ulogic := '1';
      a_write_en_i : in std_ulogic_vector(data_word_count_c - 1 downto 0) := (others => '0');
      a_address_i : in unsigned(addr_size_c - 1 downto 0);
      a_data_i : in std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
      a_data_o : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0);
      b_clock_i : in std_ulogic;
      b_enable_i : in std_ulogic := '1';
      b_write_en_i : in std_ulogic_vector(data_word_count_c - 1 downto 0) := (others => '0');
      b_address_i : in unsigned(addr_size_c - 1 downto 0);
      b_data_i : in std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
      b_data_o : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0)
      );
  end component;

  -- Dual port ram with port sizes multiple one of another.
  -- All other characteristics match ram_2p_homogeneous
  component ram_2p
    generic (
      a_addr_size_c : natural;
      a_data_byte_count_c : natural;

      b_addr_size_c : natural;
      b_data_byte_count_c : natural;

      registered_output_c : boolean := false
      );
    port (
      a_clock_i : in std_ulogic;
      a_enable_i : in std_ulogic := '1';
      a_address_i : in unsigned(a_addr_size_c-1 downto 0);
      a_write_en_i : in std_ulogic_vector(a_data_byte_count_c-1 downto 0) := (others => '1');
      a_data_i : in std_ulogic_vector(a_data_byte_count_c*8-1 downto 0) := (others => '-');
      a_data_o : out std_ulogic_vector(a_data_byte_count_c*8-1 downto 0);

      b_clock_i : in std_ulogic;
      b_enable_i : in std_ulogic := '1';
      b_address_i : in unsigned(b_addr_size_c-1 downto 0);
      b_write_en_i : in std_ulogic_vector(b_data_byte_count_c-1 downto 0) := (others => '1');
      b_data_i : in std_ulogic_vector(b_data_byte_count_c*8-1 downto 0) := (others => '-');
      b_data_o : out std_ulogic_vector(b_data_byte_count_c*8-1 downto 0)
      );
  end component;

end package ram;
