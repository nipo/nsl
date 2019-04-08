library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, hwdep, signalling;

entity i2c_mem is
  generic (
    address: std_ulogic_vector(6 downto 0);
    addr_width: integer range 1 to 16 := 8
  );
  port (
    p_i2c_o  : out signalling.i2c.i2c_o;
    p_i2c_i  : in  signalling.i2c.i2c_i
  );
end i2c_mem;

architecture arch of i2c_mem is

  constant addr_byte_cnt: integer := (addr_width - 1) / 8 + 1;

  type regs_t is
  record
    addr : unsigned(addr_width-1 downto 0);
    addr_byte_left : integer range 0 to addr_byte_cnt;
  end record;

  signal r, rin: regs_t;
  signal s_start, s_read, s_write, s_clk, s_ram_write : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(7 downto 0);
  
begin

  slave: nsl.i2c.i2c_slave_clkfree
    port map (
      p_clk_out => s_clk,

      p_i2c_i => p_i2c_i,
      p_i2c_o => p_i2c_o,

      address => address,

      p_start => s_start,

      p_r_data => s_rdata,
      p_w_data => s_wdata,
      p_r_strobe => s_read,
      p_w_strobe => s_write
    );

  ram: hwdep.ram.ram_1p
    generic map (
      addr_size => 8 * addr_byte_cnt,
      data_size => 8
    )
    port map (
      p_clk => s_clk,
      p_wen => s_ram_write,
      p_addr => std_ulogic_vector(r.addr),
      p_wdata => s_wdata,
      p_rdata => s_rdata
      );

  s_ram_write <= s_write when r.addr_byte_left = 0 else '0';

  regs: process(s_clk, s_start)
  begin
    if s_start = '1' then
      r.addr_byte_left <= addr_byte_cnt;
    elsif rising_edge(s_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(rin, s_write, s_read, s_wdata)
  begin
    rin <= r;

    if s_write = '1' then
      if r.addr_byte_left /= 0 then
        rin.addr <= r.addr(r.addr'left-8 downto 0) & unsigned(s_wdata);
        rin.addr_byte_left <= r.addr_byte_left - 1;
      else
        rin.addr <= r.addr + 1;
      end if;
    elsif s_read = '1' then
      rin.addr <= r.addr + 1;
    end if;
  end process;
end arch;
