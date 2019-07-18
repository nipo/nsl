library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package ram is

  component ram_1p
    generic (
      addr_size : natural;
      data_size : natural
      );
    port (
      p_clk   : in  std_ulogic;

      p_addr  : in  std_ulogic_vector (addr_size-1 downto 0);

      p_wen   : in  std_ulogic;
      p_wdata : in  std_ulogic_vector (data_size-1 downto 0);

      p_rdata : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

  component ram_2p_r_w
    generic (
      addr_size : natural;
      data_size : natural;
      clk_count : natural range 1 to 2 := 1;
      bypass : boolean := false;
      registered_output : boolean := false
      );
    port (
      p_clk    : in  std_ulogic_vector(0 to clk_count-1);

      p_waddr  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_wen    : in  std_ulogic := '0';
      p_wdata  : in  std_ulogic_vector (data_size-1 downto 0) := (others => '-');

      p_raddr  : in  std_ulogic_vector (addr_size-1 downto 0);
      p_ren    : in  std_ulogic := '1';
      p_rdata  : out std_ulogic_vector (data_size-1 downto 0)
      );
  end component;

  component ram_2p_homogeneous is
    generic(
      addr_size  : integer := 10;
      word_size  : integer := 8;
      data_word_count : integer := 4;
      registered_output : boolean := false
      );
    port(
      p_a_clk  : in  std_ulogic;
      p_a_en   : in  std_ulogic := '1';
      p_a_wen   : in  std_ulogic_vector(data_word_count - 1 downto 0) := (others => '0');
      p_a_addr : in  std_ulogic_vector(addr_size - 1 downto 0);
      p_a_wdata   : in  std_ulogic_vector(data_word_count * word_size - 1 downto 0) := (others => '-');
      p_a_rdata   : out std_ulogic_vector(data_word_count * word_size - 1 downto 0);
      p_b_clk  : in  std_ulogic;
      p_b_en   : in  std_ulogic := '1';
      p_b_wen   : in  std_ulogic_vector(data_word_count - 1 downto 0) := (others => '0');
      p_b_addr : in  std_ulogic_vector(addr_size - 1 downto 0);
      p_b_wdata   : in  std_ulogic_vector(data_word_count * word_size - 1 downto 0) := (others => '-');
      p_b_rdata   : out std_ulogic_vector(data_word_count * word_size - 1 downto 0)
      );
  end component;

  component ram_2p
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
      p_a_addr : in  std_ulogic_vector (a_addr_size-1 downto 0);
      p_a_wen   : in  std_ulogic_vector (a_data_byte_count-1 downto 0) := (others => '1');
      p_a_wdata : in  std_ulogic_vector (a_data_byte_count*8-1 downto 0) := (others => '-');
      p_a_rdata : out std_ulogic_vector (a_data_byte_count*8-1 downto 0);

      p_b_clk   : in  std_ulogic;
      p_b_en    : in  std_ulogic                               := '1';
      p_b_addr : in  std_ulogic_vector (b_addr_size-1 downto 0);
      p_b_wen   : in  std_ulogic_vector (b_data_byte_count-1 downto 0) := (others => '1');
      p_b_wdata : in  std_ulogic_vector (b_data_byte_count*8-1 downto 0) := (others => '-');
      p_b_rdata : out std_ulogic_vector (b_data_byte_count*8-1 downto 0)
      );
  end component;

end package ram;
