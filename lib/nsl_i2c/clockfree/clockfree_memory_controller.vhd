library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_i2c;

entity clockfree_memory_controller is
  generic (
    addr_bytes_c : integer range 1 to 4 := 2;
    data_bytes_c : integer range 1 to 4 := 1
    );
  port (
    clock_o : out std_ulogic;

    slave_address_c : in unsigned(7 downto 1);

    i2c_o : out nsl_i2c.i2c.i2c_o;
    i2c_i : in  nsl_i2c.i2c.i2c_i;

    start_o    : out std_ulogic;
    stop_o     : out std_ulogic;
    selected_o : out std_ulogic;

    addr_o : out unsigned(addr_bytes_c*8-1 downto 0);

    read_strobe_o : out std_ulogic;
    read_data_i   : in  std_ulogic_vector(data_bytes_c*8-1 downto 0);
    read_ready_i  : in  std_ulogic := '1';

    write_strobe_o : out std_ulogic;
    write_data_o   : out std_ulogic_vector(data_bytes_c*8-1 downto 0);
    write_ready_i  : in  std_ulogic := '1'
    );
end clockfree_memory_controller;

architecture arch of clockfree_memory_controller is

  type regs_t is
  record
    addr : unsigned(addr_bytes_c*8-1 downto 0);
    addr_byte_left : integer range 0 to addr_bytes_c;
    data : std_ulogic_vector(data_bytes_c*8-1 downto 0);
  end record;

  constant data_bytes_l2 : natural := nsl_math.arith.log2(data_bytes_c);

  constant addr_lsb0 : unsigned(data_bytes_l2-1 downto 0) := (others => '0');
  constant addr_lsb1 : unsigned(data_bytes_l2-1 downto 0) := (others => '1');

  signal r, rin : regs_t;
  signal start_s, read_strobe_s, write_strobe_s, write_ready_s, s_clk : std_ulogic;
  signal read_data_s, write_data_s : std_ulogic_vector(7 downto 0);
  signal is_lsb, is_msb : boolean;

begin

  clock_o <= s_clk;

  slave : nsl_i2c.clockfree.clockfree_slave
    port map (
      clock_o => s_clk,

      i2c_i => i2c_i,
      i2c_o => i2c_o,

      slave_address_c => slave_address_c,

      start_o => start_s,
      stop_o => stop_o,
      selected_o => selected_o,

      read_data_i => read_data_s,
      read_ready_i => read_ready_i,
      read_strobe_o => read_strobe_s,

      write_data_o => write_data_s,
      write_ready_i => write_ready_s,
      write_strobe_o => write_strobe_s
    );

  start_o <= start_s;

  regs : process(s_clk, start_s)
  begin
    if rising_edge(s_clk) then
      r <= rin;
    end if;
    if start_s = '1' then
      r.addr_byte_left <= addr_bytes_c;
      r.data           <= (others => '0');
      r.addr           <= to_01(r.addr, '0');
    end if;
  end process;

  transition : process(read_data_i, r, read_strobe_s, write_data_s, write_strobe_s)
    variable byte_off : integer range 0 to data_bytes_c - 1;
  begin
    rin <= r;

    byte_off := to_integer(r.addr) mod data_bytes_c;

    if write_strobe_s = '1' then
      if r.addr_byte_left = 0 then
        rin.data(byte_off*8+7 downto byte_off*8) <= write_data_s;
        rin.addr <= r.addr + 1;
      else
        rin.addr <= r.addr(r.addr'left-8 downto 0) & to_01(unsigned(write_data_s), '0');
        rin.addr_byte_left <= r.addr_byte_left - 1;
      end if;
    elsif read_strobe_s = '1' then
      rin.addr <= r.addr + 1;
      if byte_off = 0 then
        rin.data <= read_data_i;
      end if;
    end if;
  end process;

  addr_o <= r.addr(r.addr'left downto data_bytes_l2) & addr_lsb0;
  write_data_o <= write_data_s & r.data(r.data'left-8 downto 0);
  write_ready_s <= '1' when r.addr_byte_left /= 0 else write_ready_i;
  write_strobe_o <= write_strobe_s when r.addr_byte_left = 0 and is_msb else '0';
  read_strobe_o <= read_strobe_s when is_lsb else '0';

  no_lsb: if data_bytes_l2 = 0
  generate
    is_lsb <= true;
    is_msb <= true;
    read_data_s <= read_data_i;
  end generate;

  with_lsb: if data_bytes_l2 /= 0
  generate
    is_lsb <= to_01(r.addr(addr_lsb0'range), '0') = addr_lsb0;
    is_msb <= to_01(r.addr(addr_lsb1'range), '0') = addr_lsb1;
    rdata_gen : process(read_data_i, r)
      variable byte_off : integer range 0 to data_bytes_c - 1;
    begin
      byte_off := to_integer(r.addr(addr_lsb0'range));

      if byte_off = 0 then
        read_data_s <= read_data_i(7 downto 0);
      else
        read_data_s <= r.data(byte_off*8+7 downto byte_off*8);
      end if;
    end process;
  end generate;
  
end arch;
