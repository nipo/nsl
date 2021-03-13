library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

entity clockfree_control_bank is
  generic (
    control_count_c: natural range 0 to 64 := 0;
    status_count_c: natural range 0 to 64 := 0
    );
  port (
    slave_address_c: unsigned(7 downto 1);

    i2c_o: out nsl_i2c.i2c.i2c_o;
    i2c_i: in  nsl_i2c.i2c.i2c_i;
    i2c_irq_n_o : out std_ulogic;

    control_o: out nsl_i2c.clockfree.control_word_32;
    control_write_o: out std_ulogic_vector(0 to control_count_c-1);
    status_i: in nsl_i2c.clockfree.control_word_32_vector(0 to status_count_c-1);

    -- asynchronous
    raise_irq_i : in std_ulogic := '0'
    );
end entity;

architecture rtl of clockfree_control_bank is

  signal s_i2c_write, s_i2c_read, s_i2c_clk : std_ulogic;
  signal s_i2c_rdata, s_i2c_wdata : std_ulogic_vector(31 downto 0);
  signal s_i2c_address : unsigned(7 downto 0);
  signal s_i2c_start, s_i2c_stop : std_ulogic;

begin

  i2c_slave: nsl_i2c.clockfree.clockfree_memory_controller
    generic map(
      addr_bytes_c => 1,
      data_bytes_c => 4
      )
    port map (
      slave_address_c => slave_address_c,

      clock_o => s_i2c_clk,

      i2c_i => i2c_i,
      i2c_o => i2c_o,

      start_o => s_i2c_start,
      stop_o => s_i2c_stop,

      addr_o => s_i2c_address,
      read_data_i => s_i2c_rdata,
      read_strobe_o => s_i2c_read,
      write_data_o => control_o,
      write_strobe_o => s_i2c_write
    );

  i2c_irq: process(raise_irq_i, s_i2c_clk)
  begin
    if rising_edge(s_i2c_clk) then
      if s_i2c_read = '1' then
        i2c_irq_n_o <= '1';
      end if;
    end if;
    if raise_irq_i = '1' then
      i2c_irq_n_o <= '0';
    end if;
  end process;

  decoder: process(s_i2c_address, s_i2c_write, status_i, s_i2c_write)
    variable index : integer range 0 to 63;
  begin
    index := to_integer(s_i2c_address(7 downto 2));

    control_write_o <= (others => '-');
    s_i2c_rdata <= (others => '-');

    if index < status_count_c then
      s_i2c_rdata <= status_i(index);
    end if;

    if index < control_count_c then
      control_write_o(index) <= s_i2c_write;
    end if;
  end process;
  
end architecture;
