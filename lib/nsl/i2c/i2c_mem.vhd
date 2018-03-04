--  Copyright (c) 2016, Vincent Defilippi <vincentdefilippi@gmail.com>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
library hwdep;

entity i2c_mem is
  generic (
    slave_addr: std_ulogic_vector(6 downto 0);
    mem_addr_width: integer range 1 to 16 := 8
  );
  port (
    p_clk: in std_ulogic;
    p_resetn: in std_ulogic;
    p_scl: in std_ulogic;
    p_sda: in std_ulogic;
    p_scl_drain: out std_ulogic;
    p_sda_drain: out std_ulogic
  );
end i2c_mem;

architecture arch of i2c_mem is

  signal i2c_din: std_ulogic_vector(7 downto 0);
  signal i2c_dout: std_ulogic_vector(7 downto 0);

  signal i2c_read: std_ulogic;
  signal i2c_write_addr: std_ulogic;
  signal i2c_write_data: std_ulogic;
  signal i2c_write_ack: std_ulogic := '0';

  signal ram_en: std_ulogic;
  signal ram_we: std_ulogic;
  signal ram_addr: std_ulogic_vector(mem_addr_width - 1 downto 0);
  signal ram_din: std_ulogic_vector(7 downto 0);

  type state_type is (
    S_IDLE,
    S_ADDR_RECEIVED,
    S_DATA_RECEIVED,
    S_GET_MEM_ADDR,
    S_DATA_SENT,
    S_NEXT_MEM_ADDR
  );
  signal state: state_type := S_IDLE;

  constant mem_size: integer := 2 ** mem_addr_width;
  constant addr_byte_cnt: integer := (mem_addr_width - 1) / 8 + 1;

  signal addr_byte: integer range 0 to addr_byte_cnt := 0;
  signal addr_tmp: std_ulogic_vector(addr_byte_cnt * 8 - 1 downto 0) := (others => '0');
  signal addr_base: std_ulogic_vector(mem_addr_width - 1 downto 0) := (others => '0');

begin

  slave: nsl.i2c.i2c_slave
    port map (
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_scl => p_scl,
      p_sda => p_sda,
      p_scl_drain => p_scl_drain,
      p_sda_drain => p_sda_drain,

      p_start => open,
      p_stop => open,

      p_rdata => i2c_din,
      p_wdata => i2c_dout,

      p_read => i2c_read,
      p_addr => i2c_write_addr,
      p_write => i2c_write_data,
      p_wack => i2c_write_ack
    );

  ram: hwdep.ram.ram_1p
    generic map (
      addr_size => mem_addr_width,
      data_size => 8
    )
    port map (
      p_clk => p_clk,
      p_wen => ram_we,
      p_addr => ram_addr,
      p_wdata => ram_din,
      p_rdata => i2c_din
    );

  process (p_clk, p_resetn)
  begin

    if p_resetn = '0' then
      addr_base <= (others => '0');
      ram_addr <= (others => '0');
      addr_byte <= 0;
      ram_din <= (others => '0');
      ram_we <= '0';
      i2c_write_ack <= '0';
      state <= S_IDLE;

    elsif rising_edge(p_clk) then

      if i2c_write_addr = '1' then
        state <= S_ADDR_RECEIVED;

      elsif i2c_write_data = '1' then
        state <= S_DATA_RECEIVED;

      elsif i2c_read = '1' then
        state <= S_DATA_SENT;

      else
        case state is
          when S_IDLE =>
            ram_we <= '0';
            i2c_write_ack <= '0';

          when S_ADDR_RECEIVED =>
            if i2c_dout(7 downto 1) = slave_addr then
              i2c_write_ack <= '1';
              ram_addr <= addr_base;
              addr_byte <= 0;
            end if;
            state <= S_IDLE;

          when S_DATA_RECEIVED =>
            if addr_byte < addr_byte_cnt then
              addr_tmp(7 downto 0) <= i2c_dout;
              state <= S_GET_MEM_ADDR;
            else
              ram_din <= i2c_dout;
              i2c_write_ack <= '1';
              ram_we <= '1';
              state <= S_NEXT_MEM_ADDR;
            end if;

          when S_GET_MEM_ADDR =>
            if addr_byte < addr_byte_cnt - 1 then
              addr_tmp <= addr_tmp(addr_tmp'left - 8 downto 0) & "00000000";
            else
              addr_base <= addr_tmp(addr_base'range);
              ram_addr <= addr_tmp(ram_addr'range);
            end if;
            addr_byte <= addr_byte + 1;
            i2c_write_ack <= '1';
            state <= S_IDLE;

          when S_DATA_SENT =>
            state <= S_NEXT_MEM_ADDR;

          when S_NEXT_MEM_ADDR =>
            ram_we <= '0';
            i2c_write_ack <= '0';
            if ram_addr = std_ulogic_vector(to_unsigned(mem_size - 1, ram_addr'length)) then
              ram_addr <= (others => '0');
            else
              ram_addr <= std_ulogic_vector(unsigned(ram_addr) + 1);
            end if;
            state <= S_IDLE;

        end case;

      end if;
    end if;
  end process;
end arch;


