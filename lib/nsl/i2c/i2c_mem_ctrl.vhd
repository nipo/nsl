library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling, util;

entity i2c_mem_ctrl is
  generic (
    addr_bytes: integer range 1 to 4 := 2;
    data_bytes: integer range 1 to 4 := 1
  );
  port (
    p_clk : out std_ulogic;

    slave_address: in unsigned(7 downto 1);

    p_i2c_o  : out signalling.i2c.i2c_o;
    p_i2c_i  : in  signalling.i2c.i2c_i;

    p_start    : out std_ulogic;
    p_stop     : out std_ulogic;
    p_selected : out std_ulogic;

    p_addr     : out unsigned(addr_bytes*8-1 downto 0);

    p_r_strobe : out std_ulogic;
    p_r_data   : in  std_ulogic_vector(data_bytes*8-1 downto 0);
    p_r_ready  : in  std_ulogic := '1';

    p_w_strobe : out std_ulogic;
    p_w_data   : out std_ulogic_vector(data_bytes*8-1 downto 0);
    p_w_ready  : in  std_ulogic := '1'
    );
end i2c_mem_ctrl;

architecture arch of i2c_mem_ctrl is

  type regs_t is
  record
    addr : unsigned(addr_bytes*8-1 downto 0);
    addr_byte_left : integer range 0 to addr_bytes;
    data : std_ulogic_vector(data_bytes*8-1 downto 0);
  end record;

  constant data_bytes_l2 : natural := util.numeric.log2(data_bytes);
  constant addr_lsb0 : unsigned(data_bytes_l2-1 downto 0) := (others => '0');
  constant addr_lsb1 : unsigned(data_bytes_l2-1 downto 0) := (others => '1');
  
  signal r, rin: regs_t;
  signal s_start, r_strobe, w_strobe, w_ready, s_clk : std_ulogic;
  signal r_data, w_data : std_ulogic_vector(7 downto 0);
  signal is_lsb, is_msb : boolean;

begin

  p_clk <= s_clk;
  
  slave: nsl.i2c.i2c_slave_clkfree
    port map (
      p_clk_out => s_clk,

      p_i2c_i => p_i2c_i,
      p_i2c_o => p_i2c_o,

      address => slave_address,

      p_start => s_start,
      p_stop => p_stop,
      p_selected => p_selected,

      p_r_data => r_data,
      p_r_ready => p_r_ready,
      p_r_strobe => r_strobe,

      p_w_data => w_data,
      p_w_ready => w_ready,
      p_w_strobe => w_strobe
    );

  p_start <= s_start;

  regs: process(s_clk, s_start)
  begin
    if s_start = '1' then
      r.addr_byte_left <= addr_bytes;
      r.data <= (others => '0');
      r.addr <= to_01(r.addr, '0');
    elsif rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_r_data, r, r_strobe, w_data, w_strobe)
    variable byte_off : integer range 0 to data_bytes - 1;
  begin
    rin <= r;

    byte_off := to_integer(r.addr) mod data_bytes;

    if w_strobe = '1' then
      if r.addr_byte_left = 0 then
        rin.data(byte_off*8+7 downto byte_off*8) <= w_data;
        rin.addr <= r.addr + 1;
      else
        rin.addr <= r.addr(r.addr'left-8 downto 0) & to_01(unsigned(w_data), '0');
        rin.addr_byte_left <= r.addr_byte_left - 1;
      end if;
    elsif r_strobe = '1' then
      rin.addr <= r.addr + 1;
      if byte_off = 0 then
        rin.data <= p_r_data;
      end if;
    end if;
  end process;

  p_addr <= r.addr(r.addr'left downto data_bytes_l2) & addr_lsb0;
  p_w_data <= w_data & r.data(r.data'left-8 downto 0);
  w_ready <= '1' when r.addr_byte_left /= 0 else p_w_ready;
  p_w_strobe <= w_strobe when r.addr_byte_left = 0 and is_msb else '0';
  p_r_strobe <= r_strobe when is_lsb else '0';

  no_lsb: if data_bytes_l2 = 0
  generate
    is_lsb <= true;
    is_msb <= true;
    r_data <= p_r_data;
  end generate;

  with_lsb: if data_bytes_l2 /= 0
  generate
    is_lsb <= to_01(r.addr(addr_lsb0'range), '0') = addr_lsb0;
    is_msb <= to_01(r.addr(addr_lsb1'range), '0') = addr_lsb1;
    rdata_gen: process(p_r_data, r)
      variable byte_off : integer range 0 to data_bytes - 1;
    begin
      byte_off := to_integer(r.addr(addr_lsb0'range));

      if byte_off = 0 then
        r_data <= p_r_data(7 downto 0);
      else
        r_data <= r.data(byte_off*8+7 downto byte_off*8);
      end if;
    end process;
  end generate;
  
end arch;
