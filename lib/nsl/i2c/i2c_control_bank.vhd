library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling, nsl;

entity i2c_control_bank is
  generic (
    control_count: natural range 0 to 64 := 0;
    status_count: natural range 0 to 64 := 0
    );
  port (
    slave_address: std_ulogic_vector(7 downto 1);

    p_i2c_o: out signalling.i2c.i2c_o;
    p_i2c_i: in  signalling.i2c.i2c_i;
    p_i2c_irqn : out std_ulogic;


    p_control: out nsl.i2c.control_word_32;
    p_control_write: out std_ulogic_vector(0 to control_count-1);
    p_status: in nsl.i2c.control_word_32_vector(0 to status_count-1);
    -- asynchronous
    p_raise_irq : in std_ulogic := '0'
    );
end entity;

architecture rtl of i2c_control_bank is

  signal s_i2c_write, s_i2c_read, s_i2c_clk : std_ulogic;
  signal s_i2c_rdata, s_i2c_wdata : std_ulogic_vector(31 downto 0);
  signal s_i2c_address : std_ulogic_vector(7 downto 0);
  signal s_i2c_start, s_i2c_stop : std_ulogic;

begin

  i2c_slave: nsl.i2c.i2c_mem_ctrl
    generic map(
      addr_bytes => 1,
      data_bytes => 4
      )
    port map (
      slave_address => slave_address,

      p_clk => s_i2c_clk,

      p_i2c_i => p_i2c_i,
      p_i2c_o => p_i2c_o,

      p_start => s_i2c_start,
      p_stop => s_i2c_stop,

      p_addr => s_i2c_address,
      p_r_data => s_i2c_rdata,
      p_r_strobe => s_i2c_read,
      p_w_data => p_control,
      p_w_strobe => s_i2c_write
    );

  i2c_irq: process(p_raise_irq, s_i2c_clk)
  begin
    if p_raise_irq = '1' then
      p_i2c_irqn <= '0';
    elsif rising_edge(s_i2c_clk) then
      if s_i2c_read = '1' then
        p_i2c_irqn <= '1';
      end if;
    end if;
  end process;

  decoder: process(s_i2c_address, s_i2c_write)
    variable index : integer range 0 to 63;
  begin
    index := to_integer(unsigned(s_i2c_address(7 downto 2)));

    p_control_write <= (others => '-');
    s_i2c_rdata <= (others => '-');

    if index < status_count then
      s_i2c_rdata <= p_status(index);
    end if;

    if index < control_count then
      p_control_write(index) <= s_i2c_write;
    end if;
  end process;
  
end architecture;
